"""Takes the shoulder straps (pad, webbing, buckle) off the school backpack and writes them straightened into
strap space, so Godot can bend them along Henry's worn strap path (a spline mesh, as Unreal's SplineMeshComponent).
Strap space per vertex, metres: x = across, y = off the body (underside at 0), z = along the strap from the pack's
top (length_m in pack_strap.json at the pack's bottom corner). The centreline comes from geodesic distance over a k-nearest-neighbour graph of the
strap's vertices (Isomap: the mesh is in hundreds of loose pieces), then mean slices, smoothed.
Run: python3 tools/blender/build_pack_straps.py   (writes assets/characters/gear/pack_strap_{pos,neg}.glb and pack_strap.json)
"""
import heapq
import json
import os

import bpy
import bmesh  # after bpy: it is bpy's module
import mathutils
import numpy as np

SOURCE = "assets/characters/gear/school_backpack.glb"
OUT = "assets/characters/gear"
PAD = "Object_21"
WEBBING = ["Object_13", "Object_19"]
## The pad's widest point is scaled to this (owner: the old 52 mm pad was huge), metres.
PAD_WIDTH_M = 0.045
NEIGHBOURS = 10
## Source units: pieces of one strap lie closer than this to each other.
REACH = 0.25
## Points this much longer than the shortest path when routed through them are on the tail (source units).
TAIL_EXCESS = 0.35
SLICES = 60
ACROSS_CELLS = 6
SMOOTH_PASSES = 4


def load():
	bpy.ops.wm.read_factory_settings(use_empty=True)
	bpy.ops.import_scene.gltf(filepath=SOURCE)


def side_mesh(names, sign):
	"""One bmesh of the named objects' faces whose centre lies on the given x side (source space)."""
	bm = bmesh.new()
	for name in names:
		o = bpy.data.objects[name]
		part = bmesh.new()
		part.from_mesh(o.data)
		part.transform(o.matrix_world)
		drop = [f for f in part.faces if f.calc_center_median().x * sign <= 0.0]
		bmesh.ops.delete(part, geom=drop, context="FACES")
		tmp = bpy.data.meshes.new("tmp")
		part.to_mesh(tmp)
		bm.from_mesh(tmp)
		part.free()
	bm.verts.ensure_lookup_table()
	return bm


def geodesic(points, start):
	"""Dijkstra over the k-nearest-neighbour graph of points, from index start."""
	tree = mathutils.kdtree.KDTree(len(points))
	for i, p in enumerate(points):
		tree.insert(p, i)
	tree.balance()
	## Symmetric k-nearest plus everything within REACH, so loose pieces lying side by side join up.
	near = [dict() for _ in points]
	for i, p in enumerate(points):
		for (_, j, d) in tree.find_n(p, NEIGHBOURS + 1) + tree.find_range(p, REACH):
			if j != i:
				near[i][j] = d
				near[j][i] = d
	near = [list(n.items()) for n in near]
	dist = np.full(len(points), np.inf)
	dist[start] = 0.0
	heap = [(0.0, start)]
	while heap:
		d, i = heapq.heappop(heap)
		if d > dist[i]:
			continue
		for j, w in near[i]:
			if d + w < dist[j]:
				dist[j] = d + w
				heapq.heappush(heap, (d + w, j))
	return dist


def centreline(points, s):
	"""Mean of each slice of s, smoothed, then resampled evenly by arc length."""
	finite = np.isfinite(s)
	edges = np.linspace(0.0, s[finite].max(), SLICES + 1)
	nodes = []
	for a, b in zip(edges[:-1], edges[1:]):
		sel = finite & (s >= a) & (s < b)
		if sel.any():
			nodes.append(points[sel].mean(0))
	nodes = np.array(nodes)
	nodes = nodes[np.concatenate(([True], np.linalg.norm(np.diff(nodes, axis=0), axis=1) > 1e-6))]
	for _ in range(SMOOTH_PASSES):
		nodes[1:-1] = 0.25 * nodes[:-2] + 0.5 * nodes[1:-1] + 0.25 * nodes[2:]
	return nodes


def project(points, nodes):
	"""Arc length along the polyline nodes of each point's nearest projection, and that segment."""
	seg = nodes[1:] - nodes[:-1]
	lengths = np.linalg.norm(seg, axis=1)
	cum = np.concatenate(([0.0], np.cumsum(lengths)))
	best = np.full(len(points), np.inf)
	arc = np.zeros(len(points))
	index = np.zeros(len(points), dtype=int)
	for k in range(len(seg)):
		t = np.clip(((points - nodes[k]) @ seg[k]) / max(lengths[k] ** 2, 1e-12), 0.0, 1.0)
		foot = nodes[k] + t[:, None] * seg[k]
		d = np.linalg.norm(points - foot, axis=1)
		take = d < best
		best[take] = d[take]
		arc[take] = cum[k] + t[take] * lengths[k]
		index[take] = k
	return arc, index, cum


def frames(points, nodes, index, loop_centre):
	"""Per segment: tangent, outward normal (the ribbon's thin axis, pointing away from the strap loop's inside), across."""
	out = []
	for k in range(len(nodes) - 1):
		t = nodes[k + 1] - nodes[k]
		t /= max(np.linalg.norm(t), 1e-9)
		sel = points[(index >= k - 2) & (index <= k + 2)]
		if len(sel) < 3:
			out.append(out[-1] if out else (t, np.array([0.0, 0.0, 1.0]), np.cross(t, [0.0, 0.0, 1.0])))
			continue
		local = sel - sel.mean(0)
		local -= np.outer(local @ t, t)
		_, _, vt = np.linalg.svd(local, full_matrices=False)
		n = vt[1]  # vt[2] is the tangent itself (its spread was projected out)
		n -= t * (n @ t)
		if np.linalg.norm(n) < 1e-6 or not np.isfinite(n).all():
			n = out[-1][1] if out else np.array([0.0, 0.0, 1.0])
		n /= np.linalg.norm(n)
		if n @ (nodes[k] - loop_centre) < 0.0:
			n = -n
		out.append((t, n, np.cross(t, n)))
	return out


def build(sign, tag):
	pad = side_mesh([PAD], sign)
	web = side_mesh(WEBBING, sign)
	pad_count = len(pad.verts)
	bm = bmesh.new()
	for part in (pad, web):
		tmp = bpy.data.meshes.new("tmp")
		part.to_mesh(tmp)
		bm.from_mesh(tmp)
	bm.verts.ensure_lookup_table()
	points = np.array([v.co[:] for v in bm.verts])
	is_pad = np.arange(len(points)) < pad_count
	## The pad's end nearest the pack's back panel (largest y), the webbing's lowest point is the far end.
	start = int(np.argmax(np.where(is_pad, points[:, 1], -np.inf)))
	end = int(np.argmin(points[:, 2]))
	vectors = [mathutils.Vector(p) for p in points]
	s = geodesic(vectors, start)
	## The webbing's loose tail hangs off the buckle: off the shortest start-to-end path, so dropped.
	keep = s + geodesic(vectors, end) - s[end] < TAIL_EXCESS
	bmesh.ops.delete(bm, geom=[v for v, k in zip(bm.verts, keep) if not k], context="VERTS")
	bm.verts.ensure_lookup_table()
	points = points[keep]
	is_pad = is_pad[keep]
	s = s[keep]
	nodes = centreline(points, s)
	arc, index, cum = project(points, nodes)
	total = cum[-1]
	loop_centre = nodes.mean(0)
	fr = frames(points, nodes, index, loop_centre)
	u = np.zeros(len(points))
	v = np.zeros(len(points))
	for i, p in enumerate(points):
		k = index[i]
		t, n, x = fr[k]
		foot = nodes[k] + t * (arc[i] - cum[k])
		u[i] = (p - foot) @ x
		v[i] = (p - foot) @ n
	pad_width = np.percentile(np.abs(u[is_pad]), 99.0) * 2.0
	scale = PAD_WIDTH_M / pad_width
	## The underside lies on the cloth: per slice, the lowest point goes to y = 0.
	## The underside lies flat on the cloth (Godot bends it across to the jacket's curve): the lowest point of
	## each cell along and across goes to y = 0, so the pad's own curl across is taken out, its thickness kept.
	t_norm = arc / total
	bins = np.minimum((t_norm * SLICES).astype(int), SLICES - 1)
	span = np.abs(u).max() + 1e-9
	cols = np.minimum(((u / span * 0.5 + 0.5) * ACROSS_CELLS).astype(int), ACROSS_CELLS - 1)
	floor = np.full((SLICES, ACROSS_CELLS), np.nan)
	for b, c, value in zip(bins, cols, v):
		if not value >= floor[b, c]:
			floor[b, c] = value
	for b in range(SLICES):
		row = floor[b]
		good = ~np.isnan(row)
		if good.any():
			floor[b] = np.interp(np.arange(ACROSS_CELLS), np.flatnonzero(good), row[good])
		elif b > 0:
			floor[b] = floor[b - 1]
	floor = np.nan_to_num(floor)
	v = v - floor[bins, cols]
	pad_end = float(np.percentile(t_norm[is_pad], 99.5))
	for i, vert in enumerate(bm.verts):
		vert.co = mathutils.Vector((u[i] * scale, v[i] * scale, t_norm[i] * total * scale))
	mesh = bpy.data.meshes.new("pack_strap_" + tag)
	bm.to_mesh(mesh)
	obj = bpy.data.objects.new("pack_strap_" + tag, mesh)
	bpy.context.scene.collection.objects.link(obj)
	mesh.materials.append(bpy.data.materials["Backpack.002"])
	for poly in mesh.polygons:
		poly.use_smooth = True
	## Only the first UV set; Godot reads the textures from the school backpack's own import.
	while len(mesh.uv_layers) > 1:
		mesh.uv_layers.remove(mesh.uv_layers[-1])
	print(tag, "verts", len(points), "length", round(total * scale, 3), "m pad_end", round(pad_end, 3),
		"thick", round(float(np.percentile(v[is_pad], 99)) * scale, 4), "scale", round(scale, 4))
	return obj, {"length_m": float(total * scale), "pad_end": pad_end}


def export(obj, tag):
	for o in bpy.context.scene.objects:
		o.select_set(o == obj)
	bpy.context.view_layer.objects.active = obj
	bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, "pack_strap_%s.glb" % tag), use_selection=True,
		export_format="GLB", export_yup=False, export_apply=False, export_image_format="NONE")


if __name__ == "__main__":
	load()
	meta = {}
	for sign, tag in ((1.0, "pos"), (-1.0, "neg")):
		obj, info = build(sign, tag)
		meta[tag] = info
	for o in [o for o in bpy.context.scene.objects if o.name.startswith("pack_strap_")]:
		export(o, o.name.split("_")[-1])
	with open(os.path.join(OUT, "pack_strap.json"), "w") as f:
		json.dump(meta, f, indent=1)
