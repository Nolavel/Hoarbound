class_name WinterTreeMeshes
extends RefCounted
## Palm and leafless winter tree meshes shared by the Reality chunk builder and the legacy street props.
## Built from primitives, one surface per material; the same calls give byte-identical meshes.

## A palm mesh is this tall at scale 1; placements scale it to the measured height.
const PALM_BASE_HEIGHT_M: float = 9.0


## The four materials the trees use, keyed as `palm()` and `bare_tree()` expect.
static func materials() -> Dictionary:
	return {
		"palm_trunk": _mat(Color(0.36, 0.33, 0.29), 0.95),
		"palm_frond": _mat(Color(0.34, 0.33, 0.24), 0.9, true),
		"bark": _mat(Color(0.27, 0.24, 0.21), 0.95),
		"twig": _mat(Color(0.3, 0.27, 0.24), 0.95),
	}


## Palm from the Graciosa blockout: four bent trunk segments, drooping fronds; PALM_BASE_HEIGHT_M tall.
static func palm(m: Dictionary) -> ArrayMesh:
	var parts: Array = []
	var seg: float = PALM_BASE_HEIGHT_M / 4.0
	var top := Vector3(0, -0.3, 0)
	var tilt: float = 0.0
	for i: int in range(4):
		tilt += deg_to_rad(4.0 + float(i) * 1.5)
		var dir := Vector3(0, cos(tilt), -sin(tilt))
		var r: float = 0.2 - 0.03 * float(i)
		parts.append([_cyl(r, seg + 0.15, 7, r - 0.03), Transform3D(Basis(Vector3.RIGHT, -tilt), top + dir * seg * 0.5), m["palm_trunk"]])
		top += dir * seg
	for k: int in range(7):
		var yaw: float = TAU * float(k) / 7.0
		var droop: float = deg_to_rad(25.0 + float(k % 3) * 12.0)
		var b := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, droop)
		parts.append([_box(Vector3(0.45, 0.03, 3.0)), Transform3D(b, top + b * Vector3(0, 0, 1.4)), m["palm_frond"]])
	return _compose(parts)


## Leafless winter tree: trunk, five limbs and a second tier of twigs.
static func bare_tree(m: Dictionary) -> ArrayMesh:
	var parts: Array = [[_cyl(0.22, 3.2, 7, 0.15), Transform3D(Basis.IDENTITY, Vector3(0, 1.6, 0)), m["bark"]]]
	for k: int in range(5):
		var yaw: float = TAU * float(k) / 5.0 + 0.3
		var limb := Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, deg_to_rad(38.0 + float(k % 2) * 12.0))
		var base := Vector3(0, 2.6 + float(k % 3) * 0.3, 0)
		parts.append([_cyl(0.1, 2.6, 5, 0.05), Transform3D(limb, base + limb * Vector3(0, 1.3, 0)), m["bark"]])
		var tip: Vector3 = base + limb * Vector3(0, 2.4, 0)
		for j: int in range(2):
			var twig := Basis(Vector3.UP, yaw + (float(j) - 0.5) * 1.1) * Basis(Vector3.RIGHT, deg_to_rad(25.0))
			parts.append([_cyl(0.04, 1.4, 4, 0.015), Transform3D(twig, tip + twig * Vector3(0, 0.7, 0)), m["twig"]])
	return _compose(parts)


static func _mat(color: Color, roughness: float, double_sided: bool = false) -> Material:
	return StylizedEnvironmentMaterial.make(color, roughness, false, double_sided)


## Merges primitive parts into one mesh, one surface per material.
static func _compose(parts: Array) -> ArrayMesh:
	var tools: Dictionary = {}
	for part: Array in parts:
		var mat: Material = part[2]
		if not tools.has(mat):
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			tools[mat] = st
		(tools[mat] as SurfaceTool).append_from(part[0] as Mesh, 0, part[1] as Transform3D)
	var mesh := ArrayMesh.new()
	for mat: Material in tools:
		(tools[mat] as SurfaceTool).commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	return mesh


static func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


static func _cyl(radius: float, height: float, segments: int = 8, top: float = -1.0) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = radius
	c.top_radius = radius if top < 0.0 else top
	c.height = height
	c.radial_segments = segments
	c.rings = 1
	return c
