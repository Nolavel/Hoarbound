shader_type spatial;
render_mode cull_back, depth_draw_opaque;

// Snow surface around Henry. SnowClipmap rings sample one world-space height
// function: SnowField ground and settled snow near Henry, the packed field's
// prints, and outwards the chunk cover's own 2 m triangles. See docs/technical/SNOW_COVER.md.
#include "res://shaders/environment/snow/snow_surface.gdshaderinc"
#include "res://shaders/environment/snow/snow_far_cover.gdshaderinc"
#include "res://shaders/environment/snow/boot_sole.gdshaderinc"
#include "res://shaders/environment/stylized_shadow.gdshaderinc"
#include "res://shaders/environment/materials/painterly_surface.gdshaderinc"

// R: snow top (world y), G: settled depth, B: 1 where cut away, A: city wind factor.
uniform sampler2D field : filter_linear, repeat_disable;
// R: metres packed down, walls shaped to the repose slope and softened.
uniform sampler2D packed_field : filter_linear, repeat_disable;
// The accumulator before shaping: R packed, G B sole-local uv of the newest print, A its freshness.
uniform sampler2D print_field : filter_linear, repeat_disable;
uniform vec2 boot_half_m = vec2(0.1525, 0.055);
uniform sampler2D settled_normal_field : filter_linear, repeat_disable;
uniform bool use_settled_normal_field = false;
// Chunk cover lattice around the window: ground, shore fade, ground normal x and z.
uniform sampler2D far_grid : filter_nearest, repeat_disable;
uniform vec2 far_grid_origin = vec2(0.0);
uniform float far_grid_step = 2.0;
uniform bool use_far_grid = false;
uniform vec2 origin = vec2(0.0);
uniform float window_m = 25.6;
uniform float packed_texel_m = 0.05;
uniform bool use_baked_baseline = false;
uniform float sea_level_m = 0.04;
// Chebyshev distance from Henry (snow_lod.xy) over which his deformation fades out.
uniform vec2 deform_fade = vec2(4.5, 6.0);
uniform vec3 packed_color : source_color = vec3(0.5, 0.56, 0.68);
// Print walls: light scatters deep into snow and comes back blue from a cut face.
uniform vec3 wall_color : source_color = vec3(0.56, 0.66, 0.82);
// How far a broken print edge wanders off the boot's outline, metres: crust
// snaps into jagged slabs, powder crumbles in finer bites.
uniform float jag_crust_m = 0.025;
uniform float jag_powder_m = 0.01;
// Steepest a trench wall stands, as rise over run (loose snow ~40 degrees).
uniform float repose_tan = 0.84;
// Capture-only height readout (tools/runtime/capture_snow_surface.gd).
uniform bool debug_height = false;

varying vec3 v_world;
varying float v_packed;
varying float v_rim;
varying float v_cut;
varying float v_deform;
varying float v_depth;
varying float v_ground;
varying float v_city;
varying float v_crust;
varying vec2 v_jag;

// Everything the surface is at one world point; `deform` is the share of Henry's
// deformation there, fading with his distance.
struct SnowSample {
	float top;
	float ground;
	float city;
	float depth;
	float packed;
	float rim;
	float cut;
	float crust;
	float deform;
	vec2 jag;
};

float packed_at(vec2 uv) {
	return texture(packed_field, uv).r;
}

// 1 well inside the live field, 0 at its edge: a lagging rebuild never shows clamped texels.
float window_trust(vec2 xz) {
	vec2 uv = (xz - origin) / window_m;
	vec2 to_edge = min(uv, 1.0 - uv) * window_m;
	return smoothstep(0.5, 2.0, min(to_edge.x, to_edge.y));
}

// The chunk cover triangle under `xz`: corner texels and barycentric weights,
// split along the same diagonal as SnowChunkCover and SnowClipmap.
void far_triangle(vec2 xz, out ivec2 a, out ivec2 b, out ivec2 c, out vec3 w) {
	vec2 p = (xz - far_grid_origin) / far_grid_step;
	ivec2 cell = clamp(ivec2(floor(p)), ivec2(0), textureSize(far_grid, 0) - ivec2(2));
	vec2 f = clamp(p - vec2(cell), vec2(0.0), vec2(1.0));
	if (f.x + f.y <= 1.0) {
		a = cell;
		b = cell + ivec2(1, 0);
		c = cell + ivec2(0, 1);
		w = vec3(1.0 - f.x - f.y, f.x, f.y);
	} else {
		a = cell + ivec2(1, 1);
		b = cell + ivec2(0, 1);
		c = cell + ivec2(1, 0);
		w = vec3(f.x + f.y - 1.0, 1.0 - f.x, 1.0 - f.y);
	}
}

// A chunk cover vertex: terrain height lifted by snow_chunk_cover's vertex shader.
float far_corner_top(ivec2 corner) {
	vec4 g = texelFetch(far_grid, corner, 0);
	vec2 xz = far_grid_origin + vec2(corner) * far_grid_step;
	return g.r + snow_base_depth(xz, snow_city_at(xz) * g.g);
}

// UV offset that breaks a print's outline: two octaves of world noise, so the
// edge wanders like snapped snow instead of tracing the smooth sole.
vec2 edge_jag(vec2 xz, float crust) {
	vec2 a = vec2(snow_noise(xz * 9.0), snow_noise(xz * 9.0 + 31.7)) - 0.5;
	vec2 b = vec2(snow_noise(xz * 27.0 + 5.1), snow_noise(xz * 27.0 + 13.3)) - 0.5;
	return (a * 2.0 + b) * mix(jag_powder_m, jag_crust_m, crust) / window_m;
}

// Wind crust cracks into slabs that tilt up at a pit's edge. Displaced powder is
// stored in the packed field itself (negative), so only crust gets this lip.
float rim_at(vec2 uv, vec2 xz, float here, float crust) {
	float d = packed_texel_m * 2.5 / window_m;
	float around = 0.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.785398;
		around += max(packed_at(uv + vec2(cos(a), sin(a)) * d), 0.0);
		around += max(packed_at(uv + vec2(cos(a), sin(a)) * d * 0.5), 0.0) * 0.5;
	}
	around /= 12.0;
	float lip = max(around - max(here, 0.0) * 1.5, 0.0);
	float slab = 0.6 + 0.8 * snow_noise(xz * 6.0);
	return lip * mix(0.15, 0.6, crust) * slab;
}

// The drawn surface at a world point: one base surface everywhere (with the chunk
// lattice, exactly the chunk cover's 2 m triangles) plus Henry's deformation, which alone fades.
SnowSample snow_sample(vec2 xz) {
	SnowSample s;
	vec2 uv = (xz - origin) / window_m;
	vec4 f = texture(field, uv);
	float trust = window_trust(xz);
	s.deform = (1.0 - smoothstep(deform_fade.x, deform_fade.y, snow_lod_distance(xz))) * trust;
	float base_top;
	if (use_far_grid) {
		ivec2 a;
		ivec2 b;
		ivec2 c;
		vec3 w;
		far_triangle(xz, a, b, c, w);
		vec4 ga = texelFetch(far_grid, a, 0);
		vec4 gb = texelFetch(far_grid, b, 0);
		vec4 gc = texelFetch(far_grid, c, 0);
		s.ground = ga.r * w.x + gb.r * w.y + gc.r * w.z;
		s.city = snow_city_at(xz) * (ga.g * w.x + gb.g * w.y + gc.g * w.z);
		s.depth = snow_base_depth(xz, s.city);
		base_top = far_corner_top(a) * w.x + far_corner_top(b) * w.y + far_corner_top(c) * w.z;
	} else {
		// No chunk cover (scenes without the baked map): SnowField's top, thinning out at the window edge.
		s.ground = f.r - f.g;
		s.city = f.a;
		s.depth = f.g * trust;
		base_top = s.ground + f.g * trust;
	}
	s.cut = trust > 0.0 ? f.b : 0.0;
	s.crust = f.b < 0.5 ? 1.0 - smoothstep(0.45, 0.95, f.b / 0.49) : 0.0;
	s.packed = 0.0;
	s.rim = 0.0;
	s.jag = vec2(0.0);
	if (s.deform > 0.0) {
		// Walls already slope as the snow holds and are softened (snow_shape passes);
		// the outline is broken up here, where it is drawn.
		s.jag = edge_jag(xz, s.crust);
		vec2 puv = uv + s.jag;
		s.packed = packed_at(puv);
		// A fresh boot print keeps its own outline: the unshaped field, not the softened one.
		vec4 pf = texture(print_field, uv);
		s.packed = mix(s.packed, pf.r, clamp(pf.a, 0.0, 1.0) * step(0.003, pf.r));
		// The floor of a print is lumpy: grains pack unevenly under a boot.
		s.packed += (snow_noise(xz * 9.0) - 0.5) * 0.02 * smoothstep(0.02, 0.06, s.packed);
		// Pushed-aside snow heaps in crumbs, not a smooth bead.
		s.packed -= snow_noise(xz * 16.0) * 0.012 * smoothstep(0.004, 0.03, -s.packed);
		s.rim = rim_at(puv, xz, s.packed, s.crust);
	}
	s.top = max(base_top + (s.rim - s.packed) * s.deform, s.ground + 0.004);
	return s;
}

// SnowField's settled top, for shading where no chunk lattice exists.
float settled_top(vec2 xz) {
	return texture(field, (xz - origin) / window_m).r;
}

// Distance to the nearest cell border of a jittered grid (F2 - F1), for cracks.
float crack_distance(vec2 p) {
	vec2 cell = floor(p);
	float f1 = 8.0;
	float f2 = 8.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = cell + vec2(float(x), float(y));
			vec2 site = c + vec2(snow_hash(c), snow_hash(c + 17.3));
			float d = distance(p, site);
			if (d < f1) {
				f2 = f1;
				f1 = d;
			} else if (d < f2) {
				f2 = d;
			}
		}
	}
	return f2 - f1;
}

// Pit slope from the smooth packed field, never steeper than repose: shading does
// not step with the mesh triangles.
vec2 packed_slope(vec2 uv) {
	float t = packed_texel_m * 1.5 / window_m;
	float gx = packed_at(uv + vec2(t, 0.0)) - packed_at(uv - vec2(t, 0.0));
	float gz = packed_at(uv + vec2(0.0, t)) - packed_at(uv - vec2(0.0, t));
	vec2 g = vec2(gx, gz) / (2.0 * packed_texel_m * 1.5);
	float len = length(g);
	return len > repose_tan ? g * (repose_tan / len) : g;
}


void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	SnowSample s = snow_sample(world.xz);
	float top = s.top;
	// Towards its outer edge a ring morphs onto the lattice of the next, coarser one
	// (UV.x is its spacing, UV2 the band); at the edge it is that ring's surface.
	float morph = smoothstep(UV2.x, UV2.y, snow_lod_distance(world.xz));
	if (morph > 0.0) {
		float sp = UV.x;
		vec2 parity = mod(round(world.xz / sp), 2.0);
		float coarse = top;
		if (parity.x > 0.5 && parity.y > 0.5) {
			coarse = 0.5 * (snow_sample(world.xz + vec2(sp, -sp)).top + snow_sample(world.xz + vec2(-sp, sp)).top);
		} else if (parity.x > 0.5) {
			coarse = 0.5 * (snow_sample(world.xz - vec2(sp, 0.0)).top + snow_sample(world.xz + vec2(sp, 0.0)).top);
		} else if (parity.y > 0.5) {
			coarse = 0.5 * (snow_sample(world.xz - vec2(0.0, sp)).top + snow_sample(world.xz + vec2(0.0, sp)).top);
		}
		top = mix(top, coarse, morph);
	}
	VERTEX.y = top - MODEL_MATRIX[3].y;
	// The mesh has no slope of its own; the shadow normal bias needs a real up, or
	// the snow shadows itself (the old shell's blue square against the chunk cover).
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_world = vec3(world.x, top, world.z);
	v_packed = s.packed;
	v_rim = s.rim;
	v_cut = s.cut;
	v_deform = s.deform;
	v_depth = s.depth;
	v_ground = s.ground;
	v_city = s.city;
	v_crust = s.crust;
	v_jag = s.jag;
}

void fragment() {
	HFN_SHADOW_FRAGMENT(v_world);
	if (snow_lod.z > 0.0 && snow_lod_distance(v_world.xz) >= snow_lod.z + SNOW_LOD_OVERLAP_M) {
		discard;
	}
	vec2 uv = (v_world.xz - origin) / window_m;
	float ground_slope = fwidth(v_ground) / max(length(fwidth(v_world.xz)), 0.001);
	// Base: with the chunk lattice, the chunk cover's own shading, so nothing marks where it hands over.
	vec3 n;
	vec3 albedo;
	float depth;
	float thin_cut = 0.012;
	if (use_far_grid) {
		ivec2 a;
		ivec2 b;
		ivec2 c;
		vec3 w;
		far_triangle(v_world.xz, a, b, c, w);
		vec4 ga = texelFetch(far_grid, a, 0);
		vec4 gb = texelFetch(far_grid, b, 0);
		vec4 gc = texelFetch(far_grid, c, 0);
		vec3 na = vec3(ga.b, sqrt(max(1.0 - ga.b * ga.b - ga.a * ga.a, 0.0)), ga.a);
		vec3 nb = vec3(gb.b, sqrt(max(1.0 - gb.b * gb.b - gb.a * gb.a, 0.0)), gb.a);
		vec3 nc = vec3(gc.b, sqrt(max(1.0 - gc.b * gc.b - gc.a * gc.a, 0.0)), gc.a);
		snow_far_shade(v_world, na * w.x + nb * w.y + nc * w.z, ga.g * w.x + gb.g * w.y + gc.g * w.z, n, albedo, depth);
	} else {
		// Settled surface slope over ±0.4 m: the mesh facets at the 20 cm field texel
		// would band the ridges, so shade from the smoothed field instead.
		if (use_settled_normal_field) {
			n = normalize(texture(settled_normal_field, uv).rgb * 2.0 - 1.0);
		} else {
			float e = 0.4;
			float sx = settled_top(v_world.xz + vec2(e, 0.0)) - settled_top(v_world.xz - vec2(e, 0.0));
			float sz = settled_top(v_world.xz + vec2(0.0, e)) - settled_top(v_world.xz - vec2(0.0, e));
			n = normalize(vec3(-sx / (2.0 * e), 1.0, -sz / (2.0 * e)));
		}
		vec2 ripple = snow_ripple_slope(v_world.xz, v_city);
		// Near kerbs and walls the real mesh edge still matters.
		vec3 geo = normalize(cross(dFdy(v_world), dFdx(v_world)));
		n = normalize(mix(normalize(n - vec3(ripple.x, 0.0, ripple.y)), geo, smoothstep(0.6, 1.2, ground_slope)));
		depth = v_depth;
		albedo = fresh_color * (1.0 - snow_breakup(v_world, 5.0) * 0.03) * mix(1.0, 1.03, smoothstep(0.1, 0.4, depth));
		albedo = snow_thin_tint(snow_wind_tint(albedo, v_city), depth);
		thin_cut += snow_hash(floor(v_world.xz * 40.0)) * 0.02;
	}
	// Where snow thins to a skin it would z-fight the ground: let the ground show.
	// Where the ground under the snow jumps (a kerb, a wall foot) no snow surface is that steep.
	if (v_cut > 0.5 || depth < thin_cut || ground_slope > 1.5) {
		discard;
	}
	float roughness = 0.85;
	vec3 emission = vec3(0.0);
	// Henry's deformation, layered on the base: prints, rims, broken crust, the boot's tread.
	vec4 pf = texture(print_field, uv);
	float packed_px = 0.0;
	if (v_deform > 0.0) {
		// Read per pixel, not from the ring's vertices, so coarse rings keep the print's shape.
		packed_px = mix(packed_at(uv + v_jag), pf.r, clamp(pf.a, 0.0, 1.0) * step(0.003, pf.r));
	}
	float packed_height = packed_px * v_deform;
	float rim_height = v_rim * v_deform;
	if (abs(packed_height) > 0.0005 || rim_height > 0.0005) {
		vec2 raw_slope = packed_slope(uv + v_jag);
		vec2 slope = raw_slope * v_deform;
		float wall = smoothstep(0.35, 1.6, length(raw_slope)) * v_deform;
		// Pit walls are sharper than the mesh, so they also come in through the normal.
		n = normalize(n + vec3(slope.x, 0.0, slope.y) * 0.6);
		// Crust breaks along cracks that run out from a print's lip into the slab.
		float lip = smoothstep(0.003, 0.02, rim_height) + wall * 0.5 * (1.0 - smoothstep(0.02, 0.06, packed_height));
		float crack = 0.0;
		if (lip > 0.0 && v_crust > 0.0) {
			crack = (1.0 - smoothstep(0.015, 0.05, crack_distance(v_world.xz * 14.0))) * clamp(lip, 0.0, 1.0) * v_crust;
			if (crack > 0.0) {
				n = normalize(n + vec3(snow_noise(v_world.xz * 40.0) - 0.5, 0.0, snow_noise(v_world.xz * 40.0 + 7.0) - 0.5) * crack * 0.6);
			}
		}
		// The boot's outsole, exact per pixel: its uv is affine in xz, so filtering keeps it.
		float lug_groove = 0.0;
		float fresh_print = clamp(pf.a, 0.0, 1.0) * v_deform * smoothstep(0.003, 0.012, packed_height);
		if (fresh_print > 0.02) {
			mat2 dw = mat2(dFdx(v_world.xz), dFdy(v_world.xz));
			if (abs(determinant(dw)) > 1e-10) {
				mat2 to_sole = mat2(dFdx(pf.gb), dFdy(pf.gb)) * inverse(dw);
				vec2 sole = pf.gb;
				float e = 0.01;
				float edge = boot_edge_m(sole, boot_half_m);
				vec2 g_edge = vec2(boot_edge_m(sole + vec2(e, 0.0), boot_half_m) - boot_edge_m(sole - vec2(e, 0.0), boot_half_m),
					boot_edge_m(sole + vec2(0.0, e), boot_half_m) - boot_edge_m(sole - vec2(0.0, e), boot_half_m)) / (2.0 * e);
				vec2 out_xz = transpose(to_sole) * g_edge;
				// Crust breaks off near vertical; powder walls slump wider.
				float wall_w = mix(0.03, 0.012, v_crust);
				float band = smoothstep(-wall_w, -wall_w * 0.4, edge) * (1.0 - smoothstep(0.0, wall_w * 0.3, edge));
				if (dot(out_xz, out_xz) > 1e-6) {
					n = normalize(n - vec3(out_xz.x, 0.0, out_xz.y) / length(out_xz) * band * fresh_print * min(packed_height / wall_w, 2.5));
				}
				wall = max(wall, band * fresh_print);
				// Lugs press grooves into the floor; the tread fades once a pixel spans it.
				float tread = fresh_print * (1.0 - smoothstep(0.002, 0.006, length(fwidth(v_world.xz)))) * (1.0 - smoothstep(-0.006, -0.001, edge));
				if (tread > 0.01) {
					vec2 eu = vec2(0.0015) / boot_half_m;
					vec2 g_lug = vec2(boot_lug(sole + vec2(eu.x, 0.0), boot_half_m) - boot_lug(sole - vec2(eu.x, 0.0), boot_half_m),
						boot_lug(sole + vec2(0.0, eu.y), boot_half_m) - boot_lug(sole - vec2(0.0, eu.y), boot_half_m)) / (2.0 * eu);
					vec2 lug_xz = transpose(to_sole) * g_lug;
					n = normalize(n + vec3(lug_xz.x, 0.0, lug_xz.y) * 0.004 * tread);
					lug_groove = boot_lug(sole, boot_half_m) * tread;
				}
			}
		}
		float packed = smoothstep(0.01, 0.08, packed_height);
		float crust = smoothstep(0.005, 0.04, rim_height);
		float heap = smoothstep(0.004, 0.03, -packed_height);
		albedo = mix(albedo, packed_color, packed) * (1.0 - 0.1 * lug_groove) * (1.0 + crust * 0.06 + heap * 0.04);
		// Cut walls show blue and the layers of past snowfalls; cracks read as dark seams.
		float strata = 0.94 + 0.06 * sin(packed_height * 110.0 + snow_noise(v_world.xz * 4.0) * 6.0);
		albedo = mix(albedo, wall_color * strata, wall * 0.5) * (1.0 - crack * 0.22);
		roughness = mix(0.85, 0.6, packed);
		// Freshly broken grains at a print's edge sparkle more than the settled top.
		float glint = step(mix(0.996, 0.985, wall), snow_hash(floor(v_world.xz * 140.0))) * v_deform;
		emission = vec3(glint * 0.25 * (1.0 - packed * (1.0 - wall)));
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ALBEDO = hfn_painterly_surface_color(albedo, v_world, n, 0.38);
	ROUGHNESS = roughness;
	EMISSION = emission;
	if (debug_height) {
		ALBEDO = vec3(0.0);
		ROUGHNESS = 1.0;
		SPECULAR = 0.0;
		EMISSION = snow_debug_height(v_world.y);
	}
}

void light() {
	float ndotl = max(dot(NORMAL, LIGHT), 0.0);
	float attenuation = hfn_stylized_shadow(ATTENUATION, LIGHT_IS_DIRECTIONAL);
	DIFFUSE_LIGHT += ndotl * attenuation * LIGHT_COLOR / PI;
}
