extends SceneTree

## Bakes Henry's face masks into his head's UV space: R the cold flush (cheeks, a touch on the nose tip),
## G the brows (where breath rime settles). Regions are placed in Head-bone space (+Z the face, +Y up),
## measured from the head mesh's midline profile. The PNG can be retouched by hand afterwards.
## Run: godot --headless --path . --script res://tools/art/bake_henry_face_masks.gd [-- --debug]

const PLAYER: String = "res://scenes/actors/player/player.tscn"
const OUT: String = "res://assets/characters/henry/face/henry_face_masks.png"
const SIZE: int = 512
const DILATE_PX: int = 4
## Cheekbones below the eyes, either side of the nose: |x| centre, y centre, half-widths (x, y).
const CHEEK: Vector4 = Vector4(0.052, 0.108, 0.026, 0.028)
const NOSE_TIP: Vector4 = Vector4(0.0, 0.082, 0.016, 0.016)
const NOSE_SHARE: float = 0.55
## Brow ridge above the eyes.
const BROW: Vector4 = Vector4(0.036, 0.181, 0.026, 0.011)
## Only the face's front: points this far forward (z) and beyond take a mask.
const FRONT_Z: Vector2 = Vector2(0.035, 0.065)


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var player := (load(PLAYER) as PackedScene).instantiate()
	root.add_child(player)
	for _i: int in range(5):
		await process_frame
	var head := player.find_child("Henry_Head", true, false) as MeshInstance3D
	var bind: Transform3D = Transform3D.IDENTITY
	for i: int in range(head.skin.get_bind_count()):
		if head.skin.get_bind_name(i) == &"Head":
			bind = head.skin.get_bind_pose(i)
	var arrays: Array = head.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var weights: PackedColorArray = PackedColorArray()
	weights.resize(verts.size())
	for i: int in range(verts.size()):
		var q: Vector3 = bind * verts[i]
		var front: float = smoothstep(FRONT_Z.x, FRONT_Z.y, q.z)
		var flush: float = maxf(_blob(absf(q.x), q.y, CHEEK), _blob(q.x, q.y, NOSE_TIP) * NOSE_SHARE) * front
		var brow: float = _blob(absf(q.x), q.y, BROW) * front
		weights[i] = Color(flush, brow, 0.0)
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	var covered := PackedByteArray()
	covered.resize(SIZE * SIZE)
	for t: int in range(0, indices.size(), 3):
		_raster(image, covered, uvs, weights, indices[t], indices[t + 1], indices[t + 2])
	_dilate(image, covered)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT.get_base_dir()))
	image.save_png(ProjectSettings.globalize_path(OUT))
	print("FACE_MASKS wrote %s from %d triangles" % [OUT, indices.size() / 3])
	quit(0)


## Smooth elliptical falloff, 1 at the centre and about 0 at twice the half-widths.
static func _blob(x: float, y: float, region: Vector4) -> float:
	var dx: float = (x - region.x) / region.z
	var dy: float = (y - region.y) / region.w
	return exp(-(dx * dx + dy * dy))


func _raster(image: Image, covered: PackedByteArray, uvs: PackedVector2Array, weights: PackedColorArray, a: int, b: int, c: int) -> void:
	var pa: Vector2 = uvs[a] * SIZE
	var pb: Vector2 = uvs[b] * SIZE
	var pc: Vector2 = uvs[c] * SIZE
	var area: float = (pb - pa).cross(pc - pa)
	if absf(area) < 0.000001:
		return
	var lo := Vector2i(floori(minf(pa.x, minf(pb.x, pc.x))), floori(minf(pa.y, minf(pb.y, pc.y))))
	var hi := Vector2i(ceili(maxf(pa.x, maxf(pb.x, pc.x))), ceili(maxf(pa.y, maxf(pb.y, pc.y))))
	for y: int in range(maxi(lo.y, 0), mini(hi.y + 1, SIZE)):
		for x: int in range(maxi(lo.x, 0), mini(hi.x + 1, SIZE)):
			var p := Vector2(x + 0.5, y + 0.5)
			var w0: float = (pb - p).cross(pc - p) / area
			var w1: float = (pc - p).cross(pa - p) / area
			var w2: float = 1.0 - w0 - w1
			if w0 < -0.02 or w1 < -0.02 or w2 < -0.02:
				continue
			var colour: Color = weights[a] * w0 + weights[b] * w1 + weights[c] * w2
			image.set_pixel(x, y, Color(clampf(colour.r, 0.0, 1.0), clampf(colour.g, 0.0, 1.0), 0.0))
			covered[y * SIZE + x] = 1


## Grows every UV island by a few pixels so filtering at island seams never reads the black outside.
func _dilate(image: Image, covered: PackedByteArray) -> void:
	for _pass: int in range(DILATE_PX):
		var grown := covered.duplicate()
		for y: int in range(SIZE):
			for x: int in range(SIZE):
				if covered[y * SIZE + x] != 0:
					continue
				for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var n: Vector2i = Vector2i(x, y) + offset
					if n.x >= 0 and n.y >= 0 and n.x < SIZE and n.y < SIZE and covered[n.y * SIZE + n.x] != 0:
						image.set_pixel(x, y, image.get_pixel(n.x, n.y))
						grown[y * SIZE + x] = 1
						break
		covered = grown
