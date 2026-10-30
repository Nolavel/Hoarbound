extends SceneTree

## Measures the shoulder straps against the jacket and the pack in the final pose of every frame, at rest
## and moving: jacket points inside the strap, the strap's underside off the cloth, the free runs inside the
## pack or the jacket, and the gap where each strap meets the pack. Then side/front/back close-ups.
## Run: xvfb-run godot --path . --rendering-driver vulkan --fixed-fps 30 --script res://tools/runtime/measure_straps.gd -- <out dir>

## With --learn, the press each cloth point still needs is added to the strap points file.
const POINTS_FILE: String = "res://scenes/actors/player/henry/strap_points.json"
const PRESS_MARGIN_M: float = 0.0015
const PLAYER: String = "res://scenes/actors/player/player.tscn"

var _out: String = "user://shots/straps"
var _player: CharacterBody3D
var _camera: Camera3D
var _straps: PackShoulderStraps
var _jacket: MeshInstance3D
var _skeleton: Skeleton3D
var _surfaces: Array = []
var _sleeve: Array[bool] = []
## Per state name: worst figures seen.
var _stats: Dictionary = {}
var _state: String = ""
var _frame: int = 0
## Per jacket vertex: how much deeper it must be pressed to stay out of the strap in the poses seen.
var _need: Dictionary = {}


func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not args.is_empty():
		_out = args[0]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out))
	_run()


func _run() -> void:
	var floor := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = WorldBoundaryShape3D.new()
	floor.add_child(shape)
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	ground.material_override = StylizedEnvironmentMaterial.make(Color(0.78, 0.8, 0.84), 0.9)
	floor.add_child(ground)
	root.add_child(floor)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 35.0, 0.0)
	sun.shadow_enabled = true
	root.add_child(sun)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.72, 0.75, 0.8)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.72, 0.78)
	env.environment.ambient_light_energy = 0.8
	root.add_child(env)
	_player = (load(PLAYER) as PackedScene).instantiate() as CharacterBody3D
	root.add_child(_player)
	_player.global_position = Vector3(0.0, 1.0, 0.0)
	_camera = Camera3D.new()
	_camera.fov = 35.0
	root.add_child(_camera)
	await _frames(60)
	for layer: Node in root.find_children("*", "CanvasLayer", true, false):
		(layer as CanvasLayer).visible = false
	_camera.make_current()
	_skeleton = _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	_straps = _player.find_children("PackShoulderStraps", "", true, false)[0] as PackShoulderStraps
	_jacket = _skeleton.find_child("Outfit_Jacket", true, false) as MeshInstance3D
	for s: int in _jacket.mesh.get_surface_count():
		_surfaces.append(_jacket.mesh.surface_get_arrays(s))
	## Sleeve points (mostly arm-weighted): the arm pressing on the strap is reported on its own.
	var binds: Array = _straps.get(&"_binds")
	for arrays: Array in _surfaces:
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for v: int in (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
			var arm: float = 0.0
			for w: int in 4:
				var bone: String = _skeleton.get_bone_name(int(binds[bones[v * 4 + w]][0]))
				if bone.begins_with("upperarm") or bone.begins_with("lowerarm") or bone.begins_with("hand"):
					arm += weights[v * 4 + w]
			_sleeve.append(arm > 0.5)
	_skeleton.skeleton_updated.connect(_measure)
	var plan: Array = [["idle", 45, [], ""], ["walk", 60, [&"move_forward"], ""], ["sprint", 60, [&"move_forward", &"sprint"], ""],
		["stop", 30, [], ""], ["crouch", 45, [&"crouch"], ""], ["crouch_walk", 45, [&"crouch", &"move_forward"], ""],
		["turn", 45, [&"move_left"], ""], ["rest", 45, [], "shots"]]
	for step: Array in plan:
		for action: StringName in [&"move_forward", &"sprint", &"crouch", &"move_left"]:
			if action in step[2]:
				Input.action_press(action)
			else:
				Input.action_release(action)
		_state = step[0]
		await _frames(step[1])
		if step[3] == "shots":
			_state = ""
			for v: Array in [["front", 0.0], ["side", 90.0], ["back", 180.0], ["three_quarter_back", 145.0], ["shoulder", 60.0]]:
				await _shot("strap_" + v[0], v[1], 1.35, 1.1)
	for name: String in _stats:
		var st: Dictionary = _stats[name]
		print("[straps] %-12s jacket in strap %d pts (deepest %.1f mm), sleeve %d (%.1f mm) | underside off cloth %.1f..%.1f mm | free run in pack %.1f mm, in jacket %.1f mm | pack end gap %.1f mm" % [
			name, st.inside, st.deep * 1000.0, st.sleeve, st.sleeve_deep * 1000.0, st.gap_min * 1000.0, st.gap_max * 1000.0, st.pack_in * 1000.0, st.free_in * 1000.0, st.end_gap * 1000.0])
	if "--learn" in OS.get_cmdline_user_args():
		_learn()
	quit(0)


## Adds what each cloth point still needed in this run to its press in the strap points file.
func _learn() -> void:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(POINTS_FILE))
	var nv: int = (_surfaces[0][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var by_key: Dictionary = {}
	for p: Array in data["press"]:
		by_key["%d:%d" % [int(p[0]), int(p[1])]] = p
	for v: int in _need:
		var s: int = 0 if v < nv else 1
		var li: int = v if v < nv else v - nv
		var colour: Color = (_surfaces[s][Mesh.ARRAY_COLOR] as PackedColorArray)[li]
		var have: float = colour.r * PackShoulderStraps.PRESS_MAX_M
		var key: String = "%d:%d" % [s, li]
		var depth: float = minf(have + float(_need[v]), PackShoulderStraps.PRESS_MAX_M)
		if by_key.has(key):
			by_key[key][2] = snappedf(depth, 0.0001)
		else:
			var facing: bool = _faces_out(s, li)
			data["press"].append([s, li, snappedf(depth, 0.0001), facing])
	var file := FileAccess.open(POINTS_FILE, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("[straps] learned press for %d cloth points" % _need.size())


## Whether a jacket vertex's own normal faces away from the body (from spine_03, at rest).
func _faces_out(s: int, li: int) -> bool:
	var p: Vector3 = (_surfaces[s][Mesh.ARRAY_VERTEX] as PackedVector3Array)[li]
	var n: Vector3 = (_surfaces[s][Mesh.ARRAY_NORMAL] as PackedVector3Array)[li]
	var spine: Vector3 = _skeleton.get_bone_global_rest(_skeleton.find_bone(&"spine_03")).origin
	return n.dot(p - Vector3(spine.x, p.y, spine.z)) > 0.0


func _measure() -> void:
	if _state == "":
		return
	_frame += 1
	if _frame % 3 != 0:
		return
	var st: Dictionary = _stats.get(_state, {"inside": 0, "deep": 0.0, "sleeve": 0, "sleeve_deep": 0.0, "gap_min": 1.0, "gap_max": -1.0, "pack_in": -1.0, "free_in": 0.0, "end_gap": 0.0})
	_stats[_state] = st
	var cloth: PackedVector3Array = _skin_jacket()
	var canvas: BackpackModel = (_straps.get(&"_pack") as PackRig).get_canvas()
	var to_pack: Transform3D = canvas.global_transform.affine_inverse()
	for side: int in 2:
		var rows: Array = _straps.worn_rows(side)
		## Jacket points inside the strap's slab over each row's footprint (between half-way to its neighbours).
		for i: int in range(1, rows.size() - 1):
			var c: Vector3 = rows[i][1]
			var n: Vector3 = rows[i][3]
			var along: Vector3 = ((rows[i + 1][1] as Vector3) - (rows[i - 1][1] as Vector3))
			var reach: float = along.length() * 0.25
			along = along.normalized()
			var side_dir: Vector3 = ((rows[i][2] as Vector3) - (rows[i][0] as Vector3))
			var half: float = side_dir.length() * 0.5
			side_dir = side_dir.normalized()
			var below: float = -1.0
			## The band's underside across the row is a fold line through left, centre and right.
			var lh: float = ((rows[i][0] as Vector3) - c).dot(n)
			var rh: float = ((rows[i][2] as Vector3) - c).dot(n)
			for v: int in cloth.size():
				var d: Vector3 = cloth[v] - c
				var a: float = d.dot(side_dir)
				if absf(d.dot(along)) > reach or absf(a) > half:
					continue
				var h: float = d.dot(n) - (rh if a > 0.0 else lh) * absf(a) / half
				if h > PackShoulderStraps.GAP_M and h < PackShoulderStraps.GAP_M + float(rows[i][4]):
					if _sleeve[v]:
						st.sleeve += 1
						st.sleeve_deep = maxf(st.sleeve_deep, h - PackShoulderStraps.GAP_M)
						continue
					st.inside += 1
					st.deep = maxf(st.deep, h - PackShoulderStraps.GAP_M)
					_need[v] = maxf(float(_need.get(v, 0.0)), h - PackShoulderStraps.GAP_M + PRESS_MARGIN_M)
				elif h <= PackShoulderStraps.GAP_M and h > -0.02:
					below = maxf(below, h)
			## The underside's height over the highest cloth under it: the visible gap.
			if below > -1.0:
				var g: float = PackShoulderStraps.GAP_M - below
				st.gap_min = minf(st.gap_min, g)
				st.gap_max = maxf(st.gap_max, g)
		## Free runs: the band's lead-in from the pack and lead-out back to it.
		var worn: Dictionary = _straps.worn_band(side)
		var band: Array = worn["band"]
		var free: Array = band.slice(0, PackShoulderStraps.FREE_POINTS) + band.slice(band.size() - PackShoulderStraps.FREE_POINTS)
		for row: Array in free:
			for c: int in 3:
				var p: Vector3 = row[c]
				var local: Vector3 = to_pack * p
				var face: float = canvas.canvas_point(Vector3(local.x, local.y, 0.0), Vector3.FORWARD).z
				## Inside the pack: past its back face (the face is at `face`, the body side is -Z).
				if absf(local.x) < 0.17 and local.y > 0.0 and local.y < 0.52:
					st.pack_in = maxf(st.pack_in, local.z - face)
				st.free_in = maxf(st.free_in, _depth_in_cloth(p, cloth))
		for end: Array in [band[0], band[band.size() - 1]]:
			var local: Vector3 = to_pack * (end[1] as Vector3)
			st.end_gap = maxf(st.end_gap, absf(local.z - canvas.canvas_point(Vector3(local.x, local.y, 0.0), Vector3.FORWARD).z))


## How deep a point lies under the cloth: along the nearest cloth point's outward offset from the spine.
func _depth_in_cloth(p: Vector3, cloth: PackedVector3Array) -> float:
	var best: float = 1e9
	var near := Vector3.ZERO
	for q: Vector3 in cloth:
		var d: float = q.distance_squared_to(p)
		if d < best:
			best = d
			near = q
	if best > 0.03 * 0.03:
		return 0.0
	var spine: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(_skeleton.find_bone(&"spine_03")).origin
	var out: Vector3 = Vector3(near.x - spine.x, 0.0, near.z - spine.z).normalized()
	return maxf(0.0, (near - p).dot(out))


## Every jacket vertex in the final pose, skinned like the GPU.
func _skin_jacket() -> PackedVector3Array:
	var binds: Array = _straps.get(&"_binds")
	var mats: Array = []
	for b: Array in binds:
		mats.append(_skeleton.get_bone_global_pose(int(b[0])) * (b[1] as Transform3D))
	var out := PackedVector3Array()
	var xf: Transform3D = _skeleton.global_transform
	for arrays: Array in _surfaces:
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var colours: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for v: int in verts.size():
			var p := Vector3.ZERO
			var n := Vector3.ZERO
			for w: int in 4:
				var weight: float = weights[v * 4 + w]
				if weight > 0.0:
					var m: Transform3D = mats[bones[v * 4 + w]]
					p += (m * verts[v]) * weight
					n += (m.basis * normals[v]) * weight
			## The pack strap's press, as the jacket's shader applies it.
			if not colours.is_empty() and colours[v].r > 0.0:
				p -= n.normalized() * (1.0 if colours[v].g > 0.5 else -1.0) * colours[v].r * PackShoulderStraps.PRESS_MAX_M
			out.append(xf * p)
	return out


## Looks between Henry's feet (`at_y` above the soles) from `yaw` degrees round him at `dist` metres.
func _shot(shot_name: String, yaw: float, at_y: float, dist: float, wait: int = 3) -> void:
	await _frames(wait)
	var basis: Basis = _player.global_basis
	var skeleton := _player.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var feet: Vector3 = (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot_l")).origin
		+ skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone("foot_r")).origin) * 0.5
	var target: Vector3 = Vector3(feet.x, feet.y - 0.1 + at_y, feet.z)
	var dir: Vector3 = (basis * Vector3(sin(deg_to_rad(yaw)), 0.0, cos(deg_to_rad(yaw)))).normalized()
	_camera.global_position = target + dir * dist + Vector3(0.0, dist * 0.1, 0.0)
	_camera.look_at(target, Vector3.UP)
	await _frames(2)
	root.get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_out, shot_name])
	print("[shot] ", shot_name)


func _frames(count: int) -> void:
	for _i: int in range(count):
		await process_frame
