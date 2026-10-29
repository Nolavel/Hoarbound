extends Node3D

@export_range(0.0, 1.0) var burn_progress: float = 0.0
@export var autoplay: bool = true
var frame := 0
var materials: Array[ShaderMaterial] = []
var fire_light: OmniLight3D

func material(path: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load(path)
	materials.append(m)
	return m

func box(pos: Vector3, size: Vector3, color: Color) -> void:
	var node := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	node.mesh = mesh
	node.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.96
	mat.metallic = 0.12
	node.material_override = mat
	add_child(node)

func log_point(ring: int, side: int) -> Vector3:
	var a := TAU*float(side%20)/20.0
	var x := -1.55+3.1*float(ring)/8.0
	var r := 0.37*(1.0+0.08*sin(a*5.0+0.4)+0.05*sin(float(ring)*1.7+a*3.0))
	var y := minf(cos(a)*r,0.22+0.018*sin(x*3.0))
	var z := sin(a)*r
	x += (0.025*sin(a*3.0)+0.015*cos(a*7.0))*absf(float(ring)-4.0)/4.0
	return Vector3(x,y+0.48+0.015*sin(x*2.0),z)

func triangle(st: SurfaceTool,a: Vector3,b: Vector3,c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)

func build_log() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in range(8):
		for s in range(20):
			var a := log_point(ring,s)
			var b := log_point(ring,s+1)
			var c := log_point(ring+1,s)
			var d := log_point(ring+1,s+1)
			triangle(st,a,c,b)
			triangle(st,b,c,d)
	for s in range(20):
		triangle(st,Vector3(-1.55,0.48,0),log_point(0,s),log_point(0,s+1))
		triangle(st,Vector3(1.55,0.48,0),log_point(8,s+1),log_point(8,s))
	st.generate_normals()
	return st.commit()

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--progress="):
			burn_progress=clampf(float(arg.split("=")[1]),0.0,1.0)
			autoplay=false
	var env := Environment.new()
	env.background_mode=Environment.BG_COLOR
	env.background_color=Color(0.013,0.017,0.023)
	env.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color=Color(0.55,0.60,0.70)
	env.ambient_light_energy=0.8
	var we := WorldEnvironment.new()
	we.environment=env
	add_child(we)
	var camera := Camera3D.new()
	add_child(camera)
	camera.position=Vector3(2.2,1.8,6.4)
	camera.look_at(Vector3(0,1.05,-0.05))
	camera.projection=Camera3D.PROJECTION_ORTHOGONAL
	camera.size=4.85
	camera.current=true
	var key := OmniLight3D.new()
	key.position=Vector3(0.8,2.2,3.2)
	key.light_color=Color(0.83,0.87,1.0)
	key.light_energy=1.65
	key.omni_range=7.0
	add_child(key)
	# Only an open firebox and a throat: no whole stove or UI.
	box(Vector3(0,0,-0.35),Vector3(4.1,0.16,2.0),Color(0.10,0.095,0.09))
	box(Vector3(0,1.15,-1.23),Vector3(4.1,2.3,0.16),Color(0.065,0.062,0.058))
	box(Vector3(-2.0,1.15,-0.35),Vector3(0.16,2.3,1.9),Color(0.075,0.073,0.072))
	box(Vector3(2.0,1.15,-0.35),Vector3(0.16,2.3,1.9),Color(0.075,0.073,0.072))
	box(Vector3(0,2.32,-0.5),Vector3(4.1,0.18,1.6),Color(0.055,0.052,0.05))
	box(Vector3(0,0.04,0.70),Vector3(4.2,0.21,0.16),Color(0.055,0.06,0.068))
	box(Vector3(0,2.12,-0.95),Vector3(2.9,0.07,0.43),Color(0.025,0.024,0.022))
	var log_mesh := MeshInstance3D.new()
	log_mesh.mesh=build_log()
	log_mesh.material_override=material("res://wood.gdshader")
	add_child(log_mesh)
	# Two broad irregular sheets replace the eleven evenly spaced tongues.
	for i in range(2):
		var flame := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size=Vector2(3.55,1.42)
		flame.mesh=quad
		flame.position=Vector3(0,1.33,0.13-float(i)*0.29)
		var fm := material("res://flame.gdshader")
		fm.set_shader_parameter("layer",float(i))
		flame.material_override=fm
		add_child(flame)
	var smoke := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size=Vector2(2.2,1.55)
	smoke.mesh=sq
	smoke.position=Vector3(-0.25,1.35,-0.15)
	smoke.material_override=material("res://smoke.gdshader")
	add_child(smoke)
	fire_light=OmniLight3D.new()
	fire_light.position=Vector3(-0.3,0.9,0.35)
	fire_light.light_color=Color(1,0.56,0.18)
	fire_light.omni_range=4.5
	add_child(fire_light)
	apply_progress()

func _process(_delta: float) -> void:
	if autoplay:
		burn_progress=minf(float(frame)/299.0,1.0)
		frame+=1
	apply_progress()

func apply_progress() -> void:
	for m in materials:
		m.set_shader_parameter("burn_progress",burn_progress)
	var flame_energy := smoothstep(0.04,0.30,burn_progress)*(1.0-smoothstep(0.60,0.83,burn_progress))
	var ember_energy := smoothstep(0.12,0.5,burn_progress)*(1.0-smoothstep(0.76,1.0,burn_progress))*0.16
	fire_light.light_energy=(flame_energy+ember_energy)*(1.0+0.07*sin(burn_progress*163.0))*1.5
