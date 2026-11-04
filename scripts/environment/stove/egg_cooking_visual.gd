class_name EggCookingVisual
extends Node3D

## Reviewable presentation of one egg cracked into the existing 24 cm pan.
## Coordinates are relative to the pan root: +Y is up, cooking floor Y ~= 0.007 m.
## The owner of inventory/heat/cooking state can later drive seek_seconds(); this
## component neither creates food nor advances game time.

const TOTAL_SECONDS: float = 7.0
const FLOOR_Y: float = 0.0085
const EGG_Y: float = 0.185
const SHELL_RX: float = 0.028
const SHELL_RY: float = 0.021
const SHELL_RZ: float = 0.020
const SHELL_AROUND: int = 48
const SHELL_LENGTH: int = 12
const WHITE_AROUND: int = 72
const WHITE_RADIAL: int = 7

var _left: Node3D
var _right: Node3D
var _whole: MeshInstance3D
var _crack: MeshInstance3D
var _white: MeshInstance3D
var _white_material: StandardMaterial3D
var _crisp: MeshInstance3D
var _stream: MeshInstance3D
var _yolk: MeshInstance3D
var _yolk_highlight: MeshInstance3D
var _bubbles: Array[MeshInstance3D] = []
var _time: float = 0.0


func _ready() -> void:
	_build()
	seek_seconds(0.0)


func seek_seconds(seconds: float) -> void:
	_time = clampf(seconds, 0.0, TOTAL_SECONDS)
	if _left == null:
		return
	var split: float = _smooth(0.64, 1.25, _time)
	var departure: float = _smooth(2.45, 3.25, _time)
	_whole.visible = _time < 0.64
	_whole.position.y = EGG_Y
	for side: int in [-1, 1]:
		var half: Node3D = _left if side < 0 else _right
		half.position = Vector3(side * (0.038 * split + 0.055 * departure),
			EGG_Y + 0.008 * split + 0.022 * departure,
			side * 0.004 * split)
		half.rotation.z = side * deg_to_rad(43.0 * split + 12.0 * departure)
		half.rotation.y = side * deg_to_rad(32.0 * split + 9.0 * departure)
		half.visible = _time >= 0.64 and _time < 3.25
		half.get_node(^"BrokenRim").visible = split > 0.03
	_crack.visible = _time >= 0.46 and _time < 1.18
	_crack.position.y = EGG_Y
	if _crack.visible:
		_crack.mesh = _make_crack_line(_smooth(0.46, 0.68, _time))

	var spread: float = _smooth(1.34, 2.60, _time)
	_white.visible = spread > 0.0
	_crisp.visible = _time >= 3.65
	if _white.visible:
		_white.mesh = _make_white(spread, false)
		_white_material.albedo_color = Color(0.93, 0.91, 0.84).lerp(Color(0.86, 0.85, 0.79), _smooth(2.1, 5.5, _time))
	if _crisp.visible:
		_crisp.mesh = _make_white(spread, true)

	var flowing: bool = _time >= 1.08 and _time < 2.22
	_stream.visible = flowing
	if flowing:
		_stream.mesh = _make_stream(_time)

	_yolk.visible = _time >= 1.65
	_yolk_highlight.visible = _yolk.visible
	if _yolk.visible:
		var drop: float = _smooth(1.65, 2.44, _time)
		var contact: float = _smooth(2.36, 2.59, _time)
		_yolk.position = Vector3(-0.003 - 0.002 * drop,
			lerpf(EGG_Y - 0.034, FLOOR_Y + 0.012, drop), 0.005)
		_yolk.scale = Vector3(0.88, 0.88, 0.88).lerp(Vector3(1.16, 0.70, 1.11), contact)
		if contact > 0.0:
			_yolk.scale.x *= 1.0 + 0.025 * sin((_time - 2.0) * 9.5) * exp(-0.35 * (_time - 2.0))
		_yolk_highlight.global_transform = _yolk.global_transform
		_yolk_highlight.position += Vector3(-0.004, 0.007, 0.003)
		_yolk_highlight.scale = Vector3(0.25, 0.12, 0.19)
	for i: int in range(_bubbles.size()):
		var bubble: MeshInstance3D = _bubbles[i]
		bubble.visible = _time >= 2.45 and _time < 6.8
		if bubble.visible:
			var phase: float = _time * (7.0 + float(i % 4)) + float(i) * 1.63
			bubble.scale = Vector3.ONE * (0.65 + 0.35 * maxf(0.0, sin(phase)))


func _build() -> void:
	## Broad view-facing tonal bands keep the shell round in the painterly camera.
	var shell_out := ShaderMaterial.new()
	var shell_shader := Shader.new()
	shell_shader.code = """shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float lit = smoothstep(0.12, 0.78, facing);
	float paint = 0.87 + 0.13 * COLOR.r;
	ALBEDO = vec3(0.70, 0.54, 0.39) * mix(0.64, 1.15, lit) * paint;
}"""
	shell_out.shader = shell_shader
	var shell_in: Material = StylizedEnvironmentMaterial.make(Color(0.82, 0.72, 0.61), 0.93, false, true)
	var shell_rim: Material = StylizedEnvironmentMaterial.make(Color(0.60, 0.43, 0.33), 0.94, false, true)
	_whole = MeshInstance3D.new()
	_whole.name = "UnbrokenShell"
	_whole.mesh = _make_whole_shell()
	_whole.material_override = shell_out
	add_child(_whole)
	for side: int in [-1, 1]:
		var half := Node3D.new()
		half.name = "ShellLeft" if side < 0 else "ShellRight"
		add_child(half)
		var outer := MeshInstance3D.new()
		outer.name = "Outer"
		outer.mesh = _make_shell(side, false)
		outer.material_override = shell_out
		half.add_child(outer)
		var inner := MeshInstance3D.new()
		inner.name = "Inner"
		inner.mesh = _make_shell(side, true)
		inner.material_override = shell_in
		half.add_child(inner)
		var rim := MeshInstance3D.new()
		rim.name = "BrokenRim"
		rim.mesh = _make_shell_rim(side)
		rim.material_override = shell_rim
		half.add_child(rim)
		if side < 0:
			_left = half
		else:
			_right = half
	_crack = MeshInstance3D.new()
	_crack.name = "OpeningCrack"
	_crack.mesh = _make_crack_line(1.0)
	_crack.material_override = StylizedEnvironmentMaterial.make_unshaded(Color(0.22, 0.16, 0.13))
	add_child(_crack)

	_white_material = StylizedEnvironmentMaterial.make_unshaded(Color(0.93, 0.91, 0.84))
	## The procedural white mesh winds downward; render the top face as well.
	_white_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_white = MeshInstance3D.new()
	_white.name = "SpreadingWhite"
	_white.material_override = _white_material
	add_child(_white)
	_crisp = MeshInstance3D.new()
	_crisp.name = "BrowningEdge"
	_crisp.material_override = StylizedEnvironmentMaterial.make(Color(0.53, 0.34, 0.18), 0.96, false, true)
	add_child(_crisp)
	_stream = MeshInstance3D.new()
	_stream.name = "FallingAlbumen"
	var stream_material := StandardMaterial3D.new()
	stream_material.albedo_color = Color(0.93, 0.91, 0.84, 0.58)
	stream_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	stream_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stream_material.roughness = 0.8
	stream_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_stream.material_override = stream_material
	add_child(_stream)

	_yolk = MeshInstance3D.new()
	_yolk.name = "Yolk"
	var yolk_mesh := SphereMesh.new()
	yolk_mesh.radius = 0.018
	yolk_mesh.height = 0.036
	yolk_mesh.radial_segments = 32
	yolk_mesh.rings = 12
	_yolk.mesh = yolk_mesh
	_yolk.material_override = StylizedEnvironmentMaterial.make(Color(0.93, 0.51, 0.09), 0.58)
	add_child(_yolk)
	_yolk_highlight = MeshInstance3D.new()
	_yolk_highlight.name = "YolkPaintedHighlight"
	_yolk_highlight.mesh = yolk_mesh
	_yolk_highlight.material_override = StylizedEnvironmentMaterial.make_unshaded(Color(0.98, 0.81, 0.47))
	add_child(_yolk_highlight)

	var foam: Material = StylizedEnvironmentMaterial.make(Color(0.82, 0.82, 0.76), 0.91)
	for i: int in range(8):
		var bubble := MeshInstance3D.new()
		bubble.name = "SizzleBubble%02d" % i
		var mesh := SphereMesh.new()
		mesh.radius = 0.0009 + 0.00025 * float(i % 4)
		mesh.height = mesh.radius * 0.95
		mesh.radial_segments = 8
		mesh.rings = 4
		bubble.mesh = mesh
		bubble.material_override = foam
		var angle: float = float(i) * TAU / 8.0 + 0.13 * sin(float(i) * 3.0)
		var r: float = 0.050 + 0.007 * sin(float(i) * 2.2)
		bubble.position = Vector3(-0.004 + r * cos(angle), FLOOR_Y + 0.0022, r * sin(angle))
		add_child(bubble)
		_bubbles.append(bubble)


func _shell_point(side: int, lat: float, angle: float, inner: bool) -> Vector3:
	var wave: float = (0.00125 * sin(5.0 * angle + 0.2)
		+ 0.00048 * sin(11.0 * angle - 0.7)) * pow(sin(lat), 12.0)
	var inset: float = 0.0014 if inner else 0.0
	var pear: float = 1.0 + 0.13 * side * cos(lat)
	return Vector3(
		side * (SHELL_RX - inset) * cos(lat) + wave,
		(SHELL_RY - inset) * pear * sin(lat) * cos(angle),
		(SHELL_RZ - inset) * pear * sin(lat) * sin(angle)
	)


func _make_shell(side: int, inner: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in range(SHELL_LENGTH):
		var a: float = maxf(0.0001, float(row) / SHELL_LENGTH * PI * 0.5)
		var b: float = float(row + 1) / SHELL_LENGTH * PI * 0.5
		for col: int in range(SHELL_AROUND):
			var c: float = float(col) / SHELL_AROUND * TAU
			var d: float = float(col + 1) / SHELL_AROUND * TAU
			var p00: Vector3 = _shell_point(side, a, c, inner)
			var p01: Vector3 = _shell_point(side, a, d, inner)
			var p10: Vector3 = _shell_point(side, b, c, inner)
			var p11: Vector3 = _shell_point(side, b, d, inner)
			_shell_triangle(st, p00, p10, p11, side, inner)
			_shell_triangle(st, p00, p11, p01, side, inner)
	return st.commit()


func _make_whole_shell() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for row: int in range(SHELL_LENGTH * 2):
		var a: float = maxf(0.0001, float(row) / (SHELL_LENGTH * 2) * PI)
		var b: float = minf(PI - 0.0001, float(row + 1) / (SHELL_LENGTH * 2) * PI)
		for col: int in range(SHELL_AROUND):
			var c: float = float(col) / SHELL_AROUND * TAU
			var d: float = float(col + 1) / SHELL_AROUND * TAU
			var p00: Vector3 = _shell_point(1, a, c, false)
			var p01: Vector3 = _shell_point(1, a, d, false)
			var p10: Vector3 = _shell_point(1, b, c, false)
			var p11: Vector3 = _shell_point(1, b, d, false)
			_shell_triangle(st, p00, p10, p11, 1, false)
			_shell_triangle(st, p00, p11, p01, 1, false)
	return st.commit()


func _shell_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, side: int, inner: bool) -> void:
	if (side < 0) != inner:
		var old_b: Vector3 = b
		b = c
		c = old_b
	for p: Vector3 in [a, b, c]:
		var n := Vector3(p.x / (SHELL_RX * SHELL_RX),
			p.y / (SHELL_RY * SHELL_RY), p.z / (SHELL_RZ * SHELL_RZ)).normalized()
		st.set_normal(-n if inner else n)
		var warmth: float = 0.62 + 0.23 * (0.5 + 0.5 * p.y / SHELL_RY)
		warmth += 0.17 * (0.5 + 0.5 * p.x / SHELL_RX)
		warmth += 0.035 * sin(3.0 * atan2(p.z, p.y) + 18.0 * p.x)
		st.set_color(Color(warmth, warmth * 0.98, warmth * 0.94))
		st.add_vertex(p)


func _make_shell_rim(side: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(SHELL_AROUND):
		var a: float = float(i) / SHELL_AROUND * TAU
		var b: float = float(i + 1) / SHELL_AROUND * TAU
		var p0: Vector3 = _shell_point(side, PI * 0.5, a, false)
		var p1: Vector3 = _shell_point(side, PI * 0.5, b, false)
		var q0: Vector3 = _shell_point(side, PI * 0.5, a, true)
		var q1: Vector3 = _shell_point(side, PI * 0.5, b, true)
		for p: Vector3 in [p0, p1, q1, p0, q1, q0]:
			st.set_normal(Vector3(-side, 0.0, 0.0))
			st.add_vertex(p)
	return st.commit()


func _make_crack_line(fraction: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(maxi(1, int(ceil(float(SHELL_AROUND) * fraction)))):
		var a: float = float(i) / SHELL_AROUND * TAU
		var b: float = float(i + 1) / SHELL_AROUND * TAU
		var p0: Vector3 = _shell_point(1, PI * 0.5, a, false) * Vector3(1.0, 1.025, 1.025)
		var p1: Vector3 = _shell_point(1, PI * 0.5, b, false) * Vector3(1.0, 1.025, 1.025)
		var q0: Vector3 = p0 + Vector3(0.0009, 0.0, 0.0)
		var q1: Vector3 = p1 + Vector3(0.0009, 0.0, 0.0)
		for p: Vector3 in [p0, q0, q1, p0, q1, p1]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p)
	return st.commit()


func _make_white(spread: float, edge_only: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var rings: int = 2 if edge_only else WHITE_RADIAL + 1
	for row: int in range(rings):
		var radial: float = (0.945 + 0.055 * row) if edge_only else float(row) / WHITE_RADIAL
		for col: int in range(WHITE_AROUND):
			var angle: float = float(col) / WHITE_AROUND * TAU
			var outline: float = (1.0 + 0.090 * sin(3.0 * angle + 0.34)
				+ 0.056 * sin(7.0 * angle - 0.8)
				+ 0.028 * cos(12.0 * angle + 1.7))
			var hot: float = _smooth(2.6, 3.5, _time)
			var jitter: float = hot * (0.00072 * sin(10.0 * angle + _time * 18.0)
				+ 0.00038 * sin(17.0 * angle - _time * 23.0)) * pow(radial, 12.0)
			var radius: float = (0.012 + 0.052 * spread) * outline * radial + jitter
			var x: float = -0.004 + radius * cos(angle)
			var z: float = 0.001 + radius * 0.88 * sin(angle)
			var hump: float = 0.0043 * exp(-pow(radius / 0.036, 2.0))
			var ruffle: float = hot * 0.00075 * sin(7.0 * angle + 0.5 * _time) * pow(radial, 10.0)
			var rim: float = 0.0013 * pow(radial, 8.0) * hot
			verts.append(Vector3(x, FLOOR_Y + 0.0006 + hump + rim + ruffle
				+ (0.00025 if edge_only else 0.0), z))
			normals.append(Vector3.UP)
			var tint: float = 0.96 - 0.065 * radial + 0.025 * sin(3.0 * angle) * pow(radial, 2.0)
			colors.append(Color(tint, tint * (0.99 - 0.03 * radial), tint * (0.98 - 0.04 * radial)))
	if not edge_only:
		for row: int in range(rings):
			for col: int in range(WHITE_AROUND):
				var i: int = row * WHITE_AROUND + col
				var before: int = row * WHITE_AROUND + (col - 1 + WHITE_AROUND) % WHITE_AROUND
				var after: int = row * WHITE_AROUND + (col + 1) % WHITE_AROUND
				var inner: int = maxi(0, row - 1) * WHITE_AROUND + col
				var outer: int = mini(rings - 1, row + 1) * WHITE_AROUND + col
				var normal: Vector3 = (verts[after] - verts[before]).cross(verts[outer] - verts[inner]).normalized()
				normals[i] = normal if normal.y >= 0.0 else -normal
	for row: int in range(rings - 1):
		for col: int in range(WHITE_AROUND):
			var nxt: int = (col + 1) % WHITE_AROUND
			var a: int = row * WHITE_AROUND + col
			var b: int = row * WHITE_AROUND + nxt
			var c: int = (row + 1) * WHITE_AROUND + col
			var d: int = (row + 1) * WHITE_AROUND + nxt
			indices.append_array(PackedInt32Array([a, b, d, a, d, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _make_stream(seconds: float) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	var extent: float = _smooth(1.08, 1.95, seconds)
	var upper: float = EGG_Y - 0.025
	var lower: float = lerpf(upper - 0.008, FLOOR_Y + 0.005, extent)
	for row: int in range(10):
		var u: float = float(row) / 9.0
		var y: float = lerpf(upper, lower, u)
		var center: Vector2 = Vector2(-0.004 * u + 0.0012 * sin(u * 6.0 + seconds * 11.0),
			0.0018 * sin(u * 4.0))
		var radius: float = 0.0019 + 0.0030 * sin(PI * u) * (1.0 - _smooth(2.03, 2.22, seconds))
		for col: int in range(9):
			var angle: float = float(col) / 8.0 * TAU
			var n := Vector3(cos(angle), 0.0, sin(angle))
			verts.append(Vector3(center.x, y, center.y) + n * radius)
			normals.append(n)
	for row: int in range(9):
		for col: int in range(8):
			var a: int = row * 9 + col
			var b: int = a + 1
			var c: int = a + 9
			var d: int = c + 1
			indices.append_array(PackedInt32Array([a, c, d, a, d, b]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _smooth(a: float, b: float, x: float) -> float:
	var t: float = clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)
