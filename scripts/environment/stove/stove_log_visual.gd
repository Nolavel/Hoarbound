extends Node3D

## Presentation only: normalized study geometry fitted to the real 0.54 m stove log.
## It never owns fuel, temperature, capacity, ignition permission or inventory.
const WOOD := preload("res://shaders/environment/stove/log_wood.gdshader")
const FLAME := preload("res://shaders/environment/stove/log_flame.gdshader")
const SMOKE := preload("res://shaders/environment/stove/log_smoke.gdshader")
var burn_progress: float = 0.0
var _materials: Array[ShaderMaterial] = []
var _animation_seconds: float = 0.0
var _body: Node3D
var _flame_nodes: Array[MeshInstance3D] = []

func _ready() -> void:
	# Reference axis X becomes the production log's Z. Radius and length fit separately.
	var body := Node3D.new()
	_body = body
	body.rotation.y = PI * 0.5
	body.scale = Vector3(0.54/3.1,0.05/0.37,0.05/0.37)
	add_child(body)
	var log_mesh := MeshInstance3D.new()
	log_mesh.mesh = _geometry()
	log_mesh.material_override = _material(WOOD)
	body.add_child(log_mesh)
	for x: float in [-0.82,0.03,0.83]:
		var flame := MeshInstance3D.new()
		flame.mesh=_flame_geometry()
		flame.position=Vector3(x,0.21,0.40)
		var mat := _material(FLAME)
		mat.set_shader_parameter("root_x",x)
		flame.material_override=mat
		flame.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(flame)
		_flame_nodes.append(flame)
	var smoke := MeshInstance3D.new()
	var plume := SphereMesh.new()
	plume.radius=0.18
	plume.height=2.0
	plume.radial_segments=8
	plume.rings=6
	smoke.mesh=plume
	smoke.position=Vector3(-0.8,1.20,0)
	smoke.material_override=_material(SMOKE)
	smoke.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(smoke)
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

func _material(shader: Shader) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader=shader
	_materials.append(m)
	return m

func _point(ring: int, side: int) -> Vector3:
	var a: float=TAU*float(side%20)/20.0
	var x: float=-1.55+3.1*float(ring)/8.0
	var r: float=0.37*(1.0+0.08*sin(a*5.0+0.4)+0.05*sin(float(ring)*1.7+a*3.0))
	var y: float=minf(cos(a)*r,0.22+0.018*sin(x*3.0))
	x+=(0.025*sin(a*3.0)+0.015*cos(a*7.0))*absf(float(ring)-4.0)/4.0
	return Vector3(x,y+0.015*sin(x*2.0),sin(a)*r)

func _triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

func _geometry() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring: int in range(8):
		for s: int in range(20):
			var a: Vector3=_point(ring,s)
			var b: Vector3=_point(ring,s+1)
			var c: Vector3=_point(ring+1,s)
			var d: Vector3=_point(ring+1,s+1)
			_triangle(st,a,c,b)
			_triangle(st,b,c,d)
	for s: int in range(20):
		_triangle(st,Vector3(-1.55,0,0),_point(0,s),_point(0,s+1))
		_triangle(st,Vector3(1.55,0,0),_point(8,s+1),_point(8,s))
	st.generate_normals()
	return st.commit()

## Closed asymmetric tongues: a broad lower body and a curved narrow tip,
## rather than spherical lobes that read as beads from the steep TPS view.
func _flame_geometry() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	var widths: Array[float] = [0.08,0.28,0.36,0.32,0.23,0.14,0.07,0.004]
	var rings: Array[PackedVector3Array] = []
	for i: int in range(widths.size()):
		var h: float = float(i)/float(widths.size()-1)
		var ring := PackedVector3Array()
		for side: int in range(12):
			var a: float = TAU*float(side)/12.0
			ring.append(Vector3(cos(a)*widths[i]+0.15*sin(h*4.8)*h,
				-0.64+1.28*h,sin(a)*widths[i]*0.7))
		rings.append(ring)
	for i: int in range(rings.size()-1):
		for side: int in range(12):
			var j: int = (side+1)%12
			_triangle(st,rings[i][side],rings[i+1][side],rings[i][j])
			_triangle(st,rings[i][j],rings[i+1][side],rings[i+1][j])
	for side: int in range(12):
		var j: int = (side+1)%12
		_triangle(st,Vector3(0,-0.64,0),rings[0][side],rings[0][j])
		_triangle(st,Vector3(0.15*sin(4.8),0.64,0),rings[-1][j],rings[-1][side])
	st.generate_normals()
	return st.commit()


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
	var mesh_node := _body.get_child(0) as MeshInstance3D
	var vertices: PackedVector3Array = mesh_node.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var basis: Basis = Basis.from_euler(rotation_value)*_body.basis
	var bottom: float = INF
	for vertex: Vector3 in vertices:
		bottom = minf(bottom,(basis*vertex).y)
	return floor_y-bottom
