class_name IceHoleShape
extends RefCounted

## Outline of a hole in the ice, shared by collision checks and thin_ice.gdshader.
## Integer-only phases keep GDScript and the GPU on the same outline.

## Mean hole radius in metres; Henry's capsule must fit with room to thrash.
const BASE_RADIUS_M: float = 1.05


## Radius of the hole outline at an angle, in metres.
static func radius_at(tile: Vector2i, angle: float) -> float:
	var phases: Vector2 = phases_for(tile)
	var broad: float = 0.14 * sin(3.0 * angle + phases.x) + 0.08 * sin(5.0 * angle + phases.y)
	var jagged: float = 0.045 * sin(9.0 * angle + phases.x * 2.0) + 0.03 * sin(14.0 * angle + phases.y * 3.0)
	return BASE_RADIUS_M * (1.0 + broad + jagged)


## Two outline phases from the tile index; mirrored exactly in the shader.
static func phases_for(tile: Vector2i) -> Vector2:
	var a: int = posmod(tile.x * 7 + tile.y * 13, 17)
	var b: int = posmod(tile.x * 11 + tile.y * 5, 23)
	return Vector2(float(a) / 17.0 * TAU, float(b) / 23.0 * TAU)


## True when a world point lies inside a hole centred at `centre`.
static func contains(tile: Vector2i, centre: Vector3, point: Vector3) -> bool:
	var offset := Vector2(point.x - centre.x, point.z - centre.z)
	return offset.length() < radius_at(tile, atan2(offset.y, offset.x))
