## Isolated native SoftBody/Jolt experiment for #254. Not production inventory.
## Manual by default; the capture helper supplies an isolated physics configuration.
extends Node3D
var cloth: SoftBody3D
var objects: Array[RigidBody3D] = []
var frame := 0
var camera: Camera3D
var held: RigidBody3D
var drag_target := Vector3.ZERO
var cursor: ColorRect
var status: Label
var drag_events: Array = []
var target_pixel := Vector2.ZERO
var start_pixel := Vector2.ZERO
var manual := false
var carry_depth := 5.8
var object_names := ["CUBE 1", "SPHERE 1", "CUBE 2", "SPHERE 2", "CUBE 3", "SPHERE 3"]
const STAGING = [Vector3(-2.7,3.3,0),Vector3(2.7,3.3,0),Vector3(0,3.3,-2.7),Vector3(0,3.3,2.7),Vector3(-2.5,3.3,-2.5),Vector3(2.5,3.3,-2.5)]
var samples: Array = []
var verts := PackedVector3Array()
var ids := {}
var indices := PackedInt32Array()
var pins: Array[int] = []
var started: int
@export_range(0.0, 75.0) var tilt_degrees: float = 60.0
var capture_directory := "user://soft_container_lab"
var frames_directory := ""
func bag_point(p: Vector3) -> Vector3:
	return Vector3(0,3,0)+Basis(Vector3.RIGHT,deg_to_rad(tilt_degrees))*(p-Vector3(0,1.5,0))
func bag_local(p: Vector3) -> Vector3:
	return Basis(Vector3.RIGHT,deg_to_rad(-tilt_degrees))*(p-Vector3(0,3,0))+Vector3(0,1.5,0)
func staging_position(k: int) -> Vector3:
	return bag_point(Vector3(STAGING[k].x,3.65,STAGING[k].z))
func mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.75
	return m
func vertex(p: Vector3) -> int:
	var key := "%d,%d,%d" % [roundi(p.x*10000),roundi(p.y*10000),roundi(p.z*10000)]
	if ids.has(key): return ids[key]
	var n := verts.size()
	ids[key] = n
	verts.append(p)
	var bottom_rim := absf(p.y) < 0.001 and (absf(absf(p.x)-1.5) < 0.001 or absf(absf(p.z)-1.5) < 0.001)
	if p.y > 2.99 or bottom_rim: pins.append(n)
	return n
func panel(origin: Vector3, u: Vector3, v: Vector3, nu: int, nv: int) -> void:
	for j in range(nv):
		for i in range(nu):
			var a := vertex(origin + u*float(i)/nu + v*float(j)/nv)
			var b := vertex(origin + u*float(i+1)/nu + v*float(j)/nv)
			var c := vertex(origin + u*float(i+1)/nu + v*float(j+1)/nv)
			var d := vertex(origin + u*float(i)/nu + v*float(j+1)/nv)
			indices.append_array(PackedInt32Array([a,c,b,a,d,c]))
func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--capture-output="): capture_directory=arg.trim_prefix("--capture-output=")
		if arg.begins_with("--tilt="): tilt_degrees=arg.trim_prefix("--tilt=").to_float()
	capture_directory=ProjectSettings.globalize_path(capture_directory)
	frames_directory=capture_directory.path_join("frames")
	started = Time.get_ticks_msec()
	DirAccess.make_dir_recursive_absolute(frames_directory)
	panel(Vector3(-1.5,0,-1.5),Vector3(3,0,0),Vector3(0,3,0),28,32)
	panel(Vector3(1.5,0,1.5),Vector3(-3,0,0),Vector3(0,3,0),28,32)
	panel(Vector3(-1.5,0,1.5),Vector3(0,0,-3),Vector3(0,3,0),28,32)
	panel(Vector3(1.5,0,-1.5),Vector3(0,0,3),Vector3(0,3,0),28,32)
	panel(Vector3(-1.5,0,1.5),Vector3(3,0,0),Vector3(0,0,-3),28,28)
	var normals := PackedVector3Array()
	normals.resize(verts.size())
	for i in range(0,indices.size(),3):
		var a := indices[i]; var b := indices[i+1]; var c := indices[i+2]
		var n := (verts[c]-verts[a]).cross(verts[b]-verts[a]).normalized()
		normals[a] += n; normals[b] += n; normals[c] += n
	for i in normals.size(): normals[i] = normals[i].normalized()
	var arrays := []; arrays.resize(Mesh.ARRAY_MAX)
	var uv := PackedVector2Array()
	for p in verts: uv.append(Vector2((p.x+p.z)*28.0/3.0,(p.z*28.0/3.0 if absf(p.y)<0.001 else p.y*32.0/3.0)))
	for i in verts.size():
		verts[i]=bag_point(verts[i])
		normals[i]=Basis(Vector3.RIGHT,deg_to_rad(tilt_degrees))*normals[i]
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_VERTEX] = verts; arrays[Mesh.ARRAY_NORMAL] = normals; arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new(); mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	cloth = SoftBody3D.new(); cloth.mesh = mesh; cloth.collision_mask=3
	cloth.total_mass = 1.5; cloth.linear_stiffness = 0.65
	cloth.pressure_coefficient = 0.0; cloth.damping_coefficient = 0.02
	cloth.simulation_precision = 40
	var shader := Shader.new()
	shader.code = "shader_type spatial; render_mode cull_disabled; void fragment(){ vec2 g=abs(fract(UV+0.5)-0.5)/max(fwidth(UV),vec2(0.001)); float line=1.0-smoothstep(0.5,1.3,min(g.x,g.y)); ALBEDO=mix(vec3(0.25,0.62,0.69),vec3(0.025,0.08,0.10),line); EMISSION=ALBEDO*0.15; ROUGHNESS=0.85; }"
	var sm := ShaderMaterial.new(); sm.shader = shader
	cloth.material_override = sm
	add_child(cloth)
	for i in pins: cloth.set_point_pinned(i,true)
	# Godot 4.6 initializes Jolt vertex radius on space transition, not construction.
	# Reattach before the first physics step so the configured collision thickness applies.
	PhysicsServer3D.soft_body_set_space(cloth.get_physics_rid(), RID())
	PhysicsServer3D.soft_body_set_space(cloth.get_physics_rid(), get_world_3d().space)
	var floor_body := StaticBody3D.new(); floor_body.collision_mask=3; floor_body.position.y = -2.0
	var floor_shape := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(30,0.2,30); floor_shape.shape=bs
	floor_body.add_child(floor_shape); add_child(floor_body)
	var floor_mesh := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size=bs.size; floor_mesh.mesh=bm; floor_mesh.material_override=mat(Color(0.12,0.15,0.20)); floor_body.add_child(floor_mesh)
	var light := DirectionalLight3D.new(); light.rotation_degrees=Vector3(-45,-30,0); light.light_energy=1.5; add_child(light)
	var env := WorldEnvironment.new(); env.environment=Environment.new(); env.environment.background_mode=Environment.BG_COLOR; env.environment.background_color=Color(0.045,0.06,0.085); env.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR; env.environment.ambient_light_color=Color(0.65,0.75,0.9); env.environment.ambient_light_energy=0.65; add_child(env)
	camera = Camera3D.new(); add_child(camera)
	camera.position = Vector3(0,3,0)+(Basis(Vector3.RIGHT,deg_to_rad(tilt_degrees))*Vector3.UP)*14; camera.look_at(Vector3(0,3,0),Basis(Vector3.RIGHT,deg_to_rad(tilt_degrees))*Vector3.FORWARD)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE; camera.fov = 38.0; camera.make_current()
	for k in 6:
		var shelf := StaticBody3D.new(); shelf.collision_mask=3; shelf.position = staging_position(k)-Vector3.UP*0.65
		var shape := BoxShape3D.new(); shape.size=Vector3(1.3,0.2,1.3)
		var collision := CollisionShape3D.new(); collision.shape=shape; shelf.add_child(collision)
		var visual := MeshInstance3D.new(); var shelf_mesh := BoxMesh.new(); shelf_mesh.size=shape.size; visual.mesh=shelf_mesh; visual.material_override=mat(Color(0.23,0.28,0.34)); shelf.add_child(visual); add_child(shelf)
		spawn_object(k)
	var title := Label.new(); title.text="CONTAINER TILTED %.0f DEG / GRAVITY DOWN" % tilt_degrees; title.position=Vector2(24,16); title.add_theme_font_size_override("font_size",26); add_child(title)
	status=Label.new(); status.position=Vector2(24,1025); status.add_theme_font_size_override("font_size",22); add_child(status)
	cursor=ColorRect.new(); cursor.size=Vector2(12,12); cursor.color=Color(1,0.9,0.15); cursor.mouse_filter=Control.MOUSE_FILTER_IGNORE; add_child(cursor)
	manual = not "--capture" in OS.get_cmdline_user_args()
	status.text="LMB: pick up / move over opening / release to drop"
	if not manual: capture_loop.call_deferred()
func spawn_object(slot: int) -> void:
	var kind := slot % 2
	var body := RigidBody3D.new(); body.mass=1.0; body.continuous_cd=true; body.collision_layer=2; body.collision_mask=3
	var mesh: PrimitiveMesh
	var shape: Shape3D
	if kind==0:
		var b := BoxMesh.new(); b.size=Vector3(1.02,0.84,0.96); mesh=b
		var s := BoxShape3D.new(); s.size=b.size; shape=s
	elif kind==1:
		var b := SphereMesh.new(); b.radius=0.54; b.height=1.08; mesh=b
		var s := SphereShape3D.new(); s.radius=0.54; shape=s
	var visual := MeshInstance3D.new(); visual.mesh=mesh; visual.material_override=mat([Color(0.95,0.46,0.16),Color(0.4,0.78,0.28),Color(0.74,0.36,0.84)][kind]); body.add_child(visual)
	var collider := CollisionShape3D.new(); collider.shape=shape; body.add_child(collider)
	body.position=staging_position(slot); body.rotation=Vector3.ZERO
	add_child(body); objects.append(body)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		cursor.position=event.position-Vector2(6,6)
		if is_instance_valid(held): update_drag_target(event.position)
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		cursor.position=event.position-Vector2(6,6)
		if event.pressed:
			var origin := camera.project_ray_origin(event.position)
			var query := PhysicsRayQueryParameters3D.create(origin,origin+camera.project_ray_normal(event.position)*100,2)
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if not hit.is_empty() and hit.collider is RigidBody3D:
				held=hit.collider; held.sleeping=false
				update_drag_target(event.position)
				drag_events.append({"frame":frame,"event":"pick","body":objects.find(held)})
		else:
			if is_instance_valid(held): drag_events.append({"frame":frame,"event":"release","body":objects.find(held),"position":[held.position.x,held.position.y,held.position.z]})
			held=null
func update_drag_target(pixel: Vector2) -> void:
	var point = Plane((Basis(Vector3.RIGHT,deg_to_rad(tilt_degrees))*Vector3.UP),(Basis(Vector3.RIGHT,deg_to_rad(tilt_degrees))*Vector3.UP).dot(bag_point(Vector3(0,carry_depth,0)))).intersects_ray(camera.project_ray_origin(pixel),camera.project_ray_normal(pixel))
	if point != null: drag_target=point
func _physics_process(_delta: float) -> void:
	if is_instance_valid(held):
		# Critically damped physical spring; collision response stays enabled.
		held.apply_central_force((drag_target-held.global_position)*100.0-held.linear_velocity*20.0+Vector3.UP*9.8*held.mass)
func mouse_move(pixel: Vector2) -> void:
	var e := InputEventMouseMotion.new(); e.position=pixel; e.global_position=pixel; e.button_mask=MOUSE_BUTTON_MASK_LEFT if is_instance_valid(held) else 0
	Input.parse_input_event(e)
func mouse_button(pixel: Vector2, pressed: bool) -> void:
	var e := InputEventMouseButton.new(); e.position=pixel; e.global_position=pixel; e.button_index=MOUSE_BUTTON_LEFT; e.pressed=pressed
	Input.parse_input_event(e)
func choose_drop(slot: int) -> Vector3:
	# Aim at the upper part of the tilted opening. World gravity then carries
	# each body through the aperture toward the lower side of the bag.
	var best := Vector3.ZERO
	var best_score := -INF
	for ix in 9:
		var local_target := Vector3(lerpf(-0.72,0.72,float(ix)/8),3.65,-0.85)
		var score := 10.0
		for k in slot:
			var p := bag_local(objects[k].position)
			score=minf(score,absf(local_target.x-p.x)-0.2*p.y)
		if score>best_score:
			best_score=score; best=bag_point(local_target)
	return best
func capture_loop() -> void:
	for f in range(648):
		frame=f
		var slot := int(f/96)
		var phase := f%96
		if slot<6:
			if phase==12:
				carry_depth=5.8
				start_pixel=camera.unproject_position(objects[slot].global_position)
				target_pixel=camera.unproject_position(choose_drop(slot))
				mouse_move(start_pixel); mouse_button(start_pixel,true)
				status.text="PICK UP "+object_names[slot]+" / lift above rim"
			elif phase>12 and phase<24:
				mouse_move(start_pixel)
			elif phase>=24 and phase<48:
				var t := smoothstep(0,1,float(phase-24)/23)
				mouse_move(start_pixel.lerp(target_pixel,t))
				status.text="DRAG "+object_names[slot]+" / aim for unoccupied space"
			elif phase>=48 and phase<66:
				carry_depth=lerpf(5.8,3.65,smoothstep(0,1,float(phase-48)/17))
				mouse_move(target_pixel)
			elif phase>=66 and phase<86:
				carry_depth=3.65
				mouse_move(target_pixel)
			elif phase==86:
				mouse_button(target_pixel,false)
				status.text="RELEASE "+object_names[slot]+" / gravity + Jolt contacts"
		else: status.text="SETTLING / 6 objects / gravity settling / native SoftBody + Jolt"
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(frames_directory.path_join("frame_%04d.png"%f))
		var pos := []
		for body in objects: pos.append([body.position.x,body.position.y,body.position.z])
		samples.append({"frame":f,"time":float(f)/24,"positions":pos,"held":objects.find(held)})
		await get_tree().process_frame
	var file := FileAccess.open(capture_directory.path_join("capture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"engine":Engine.get_version_info(),"physics":"Jolt Physics","container_tilt_degrees":tilt_degrees,"gravity":"world -Y","frames":648,"fps":24,"events":drag_events,"samples":samples},"\t"))
	get_tree().quit()
