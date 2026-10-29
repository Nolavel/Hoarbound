class_name SnowTrackStore
extends RefCounted
## Snow deformation that left Henry's window, kept as coarse world tiles with the
## fill clock they were stored at; restored with the fill-in since then applied at once.
## Persistence v3 stores compression, displaced mass, broken crust and density.
## Old signed v1 / two-channel v2 saves remain readable.

## Side of one tile in metres; the window moves in steps of this size.
const TILE_M: float = 3.2
## Texels along one tile side (10 cm each).
const TILE_TEX: int = 64
const LEGACY_TILE_TEX: int = 32
## Metres per stored byte step for compression and displaced mass.
const DEPTH_STEP_M: float = 0.005
## Legacy byte that meant zero in the old signed one-channel save format.
const ZERO_BYTE: int = 32
const FORMAT_VERSION: int = 3
const CHANNELS: int = 4
## Tiles kept at most; the longest-filled ones go first.
const MAX_TILES: int = 4096
## Deformation below this after fill-in is not worth keeping, metres.
const MIN_DEFORM_M: float = 0.01

## Tile key -> [clock stamp, PackedByteArray]. V3: 64x64 RGBA.
## V2: 32x32 RG; V1: 32x32 signed R/G.
var tiles: Dictionary = {}
## Fill-in done so far, as -ln(share left); deformation left after a span is exp(-Δ).
var clock: float = 0.0


## Advances the fill clock by one frame's fill share.
func advance(fill: float) -> void:
	clock += -log(maxf(1.0 - clampf(fill, 0.0, 0.999999), 1e-6))


## Files every tile of `field` (RG metres, BA 0..1) that lies outside
## `keep`, the window that stays on screen.
func store(field: Image, origin: Vector2, window_m: float, keep: Rect2) -> void:
	var tiles_across: int = roundi(window_m / TILE_M)
	var px: int = field.get_width() / tiles_across
	for ty: int in range(tiles_across):
		for tx: int in range(tiles_across):
			var corner: Vector2 = origin + Vector2(tx, ty) * TILE_M
			if keep.has_area() and keep.encloses(Rect2(corner, Vector2.ONE * TILE_M)):
				continue
			var region: Image = field.get_region(Rect2i(tx * px, ty * px, px, px))
			region.resize(TILE_TEX, TILE_TEX, Image.INTERPOLATE_BILINEAR)
			var bytes := PackedByteArray()
			bytes.resize(TILE_TEX * TILE_TEX * CHANNELS)
			var any: bool = false
			var full_state: bool = field.get_format() != Image.FORMAT_RGF and field.get_format() != Image.FORMAT_RF
			for y: int in range(TILE_TEX):
				for x: int in range(TILE_TEX):
					var state: Color = region.get_pixel(x, y)
					var i: int = (y * TILE_TEX + x) * CHANNELS
					var compression: int = clampi(roundi(maxf(state.r, 0.0) / DEPTH_STEP_M), 0, 255)
					var displaced: int = clampi(roundi(maxf(state.g, 0.0) / DEPTH_STEP_M), 0, 255)
					var broken: int = clampi(roundi(clampf(state.b, 0.0, 1.0) * 255.0), 0, 255) if full_state else 0
					var dense: int = clampi(roundi(clampf(state.a, 0.0, 1.0) * 255.0), 0, 255) if full_state else 0
					bytes[i] = compression
					bytes[i + 1] = displaced
					bytes[i + 2] = broken
					bytes[i + 3] = dense
					any = any or compression != 0 or displaced != 0 or broken != 0 or dense != 0
			var key: Vector2i = tile_key(corner + Vector2.ONE * TILE_M * 0.5)
			if any:
				tiles[key] = [clock, bytes]
			else:
				tiles.erase(key)
	_trim()


## Restore full RGBA deformation: B/A weather-age slower than R/G.
## Accepts the old signed 1-channel and v2 R/G tile formats.
func restore(origin: Vector2, window_m: float, side: int) -> Image:
	var out := Image.create_empty(side, side, false, Image.FORMAT_RGBAF)
	var tiles_across: int = roundi(window_m / TILE_M)
	var px: int = side / tiles_across
	for ty: int in range(tiles_across):
		for tx: int in range(tiles_across):
			var key: Vector2i = tile_key(origin + (Vector2(tx, ty) + Vector2(0.5, 0.5)) * TILE_M)
			if not tiles.has(key):
				continue
			var entry: Array = tiles[key]
			var age: float = maxf(clock - float(entry[0]), 0.0)
			var left: float = exp(-age)
			var left_b: float = exp(-age * 0.72)
			var left_a: float = exp(-age * 0.42)
			if left < 0.000001 and left_b < 0.000001 and left_a < 0.000001:
				continue
			var bytes: PackedByteArray = entry[1]
			var source_side: int = TILE_TEX
			var channels: int = CHANNELS
			if bytes.size() == LEGACY_TILE_TEX * LEGACY_TILE_TEX * 2:
				source_side = LEGACY_TILE_TEX
				channels = 2
			elif bytes.size() == LEGACY_TILE_TEX * LEGACY_TILE_TEX:
				source_side = LEGACY_TILE_TEX
				channels = 1
			elif bytes.size() != TILE_TEX * TILE_TEX * CHANNELS:
				continue
			var small := Image.create_empty(source_side, source_side, false, Image.FORMAT_RGBAF)
			for i: int in range(source_side * source_side):
				var compression: float = 0.0
				var displaced: float = 0.0
				var disturbed: float = 0.0
				var density: float = 0.0
				if channels == CHANNELS:
					compression = float(bytes[i * channels]) * DEPTH_STEP_M * left
					displaced = float(bytes[i * channels + 1]) * DEPTH_STEP_M * left
					disturbed = float(bytes[i * channels + 2]) / 255.0 * left_b
					density = float(bytes[i * channels + 3]) / 255.0 * left_a
				elif channels == 2:
					compression = float(bytes[i * channels]) * DEPTH_STEP_M * left
					displaced = float(bytes[i * channels + 1]) * DEPTH_STEP_M * left
				else:
					var signed_steps: int = int(bytes[i]) - ZERO_BYTE
					compression = float(maxi(signed_steps, 0)) * DEPTH_STEP_M * left
					displaced = float(maxi(-signed_steps, 0)) * DEPTH_STEP_M * left
				small.set_pixel(i % source_side, i / source_side, Color(compression, displaced, disturbed, density))
			small.resize(px, px, Image.INTERPOLATE_BILINEAR)
			out.blit_rect(small, Rect2i(0, 0, px, px), Vector2i(tx * px, ty * px))
	return out


static func tile_key(at: Vector2) -> Vector2i:
	return Vector2i(floori(at.x / TILE_M), floori(at.y / TILE_M))


func get_save_data() -> Dictionary:
	var out: Dictionary = {}
	for key: Vector2i in tiles:
		var entry: Array = tiles[key]
		out["%d:%d" % [key.x, key.y]] = [entry[0], Marshalls.raw_to_base64(entry[1])]
	return {
		"format_version": FORMAT_VERSION,
		"channels": CHANNELS,
		"depth_step_m": DEPTH_STEP_M,
		"clock": clock,
		"tiles": out,
		"zero_byte": ZERO_BYTE,
	}


func load_save_data(data: Dictionary) -> void:
	tiles.clear()
	clock = float(data.get("clock", 0.0))
	var saved: Dictionary = data.get("tiles", {})
	var version: int = int(data.get("format_version", 1))
	var saved_zero: int = int(data.get("zero_byte", 0))
	for name: String in saved:
		var parts: PackedStringArray = name.split(":")
		var entry: Array = saved[name]
		if parts.size() != 2 or entry.size() != 2:
			continue
		var bytes: PackedByteArray = Marshalls.base64_to_raw(String(entry[1]))
		if version >= FORMAT_VERSION and bytes.size() == TILE_TEX * TILE_TEX * CHANNELS:
			tiles[Vector2i(int(parts[0]), int(parts[1]))] = [float(entry[0]), bytes]
		elif version == 2 and bytes.size() == LEGACY_TILE_TEX * LEGACY_TILE_TEX * 2:
			tiles[Vector2i(int(parts[0]), int(parts[1]))] = [float(entry[0]), bytes]
		elif bytes.size() == LEGACY_TILE_TEX * LEGACY_TILE_TEX:
			## Normalize the earliest signed-byte format.
			var lift: int = ZERO_BYTE - saved_zero
			if lift != 0:
				for i: int in range(bytes.size()):
					bytes[i] = clampi(int(bytes[i]) + lift, 0, 255)
			tiles[Vector2i(int(parts[0]), int(parts[1]))] = [float(entry[0]), bytes]


## Drops the tiles that have filled in longest once the store is full.
func _trim() -> void:
	if tiles.size() <= MAX_TILES:
		return
	var keys: Array = tiles.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return float(tiles[a][0]) < float(tiles[b][0]))
	for i: int in range(tiles.size() - MAX_TILES):
		tiles.erase(keys[i])
