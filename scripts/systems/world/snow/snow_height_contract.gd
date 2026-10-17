class_name SnowHeightContract
extends RefCounted
## Shared CPU contract for snow height and local world-space mapping.
## Rendering backends may change, but they must preserve these meanings.


static func base_top(ground_height: float, settled_depth: float) -> float:
	return ground_height + maxf(settled_depth, 0.0)


static func visible_depth(
	settled_depth: float, compression_m: float = 0.0, displaced_m: float = 0.0
) -> float:
	return maxf(
		maxf(settled_depth, 0.0) + maxf(displaced_m, 0.0) - maxf(compression_m, 0.0),
		0.0
	)


static func visible_top(
	ground_height: float,
	settled_depth: float,
	compression_m: float = 0.0,
	displaced_m: float = 0.0
) -> float:
	return ground_height + visible_depth(settled_depth, compression_m, displaced_m)


static func depth_from_top(ground_height: float, snow_top: float) -> float:
	return maxf(snow_top - ground_height, 0.0)


static func world_to_uv(at: Vector2, origin: Vector2, window_m: float) -> Vector2:
	if window_m <= 0.0:
		return Vector2(INF, INF)
	return (at - origin) / window_m


static func uv_to_world(uv: Vector2, origin: Vector2, window_m: float) -> Vector2:
	return origin + uv * window_m


static func contains_world(at: Vector2, origin: Vector2, window_m: float) -> bool:
	var uv: Vector2 = world_to_uv(at, origin, window_m)
	return uv.x >= 0.0 and uv.y >= 0.0 and uv.x < 1.0 and uv.y < 1.0


static func snapped_window_origin(centre: Vector2, window_m: float, texel_m: float) -> Vector2:
	var half: float = window_m * 0.5
	if texel_m <= 0.0:
		return centre - Vector2.ONE * half
	return Vector2(
		snappedf(centre.x - half, texel_m),
		snappedf(centre.y - half, texel_m)
	)
