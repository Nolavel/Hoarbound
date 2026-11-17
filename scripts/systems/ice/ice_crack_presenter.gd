class_name IceCrackPresenter
extends Node

## Draws and sounds what IceField decides: creak, spreading cracks, the hole.
## Reads the field only; crack growth is presentation memory and never written back.

## Emitted once a hole opens, with the hole's centre on the ice surface.
signal hole_opened(tile: Vector2i, centre: Vector3)
## Emitted when the cracks under the player grow by a visible step.
signal crack_grew(tile: Vector2i, growth: float)
## Asks whoever owns the camera for a short shake; strength is 0..1.
signal shake_requested(strength: float, seconds: float)

## Growth shown at the first crack, so the CRACKING warning is never invisible.
const FIRST_CRACK_GROWTH: float = 0.15
## Growth steps that each trigger a crack sound and a shake.
const CRACK_STEP: float = 0.2
## Seconds without a load report before the creak loop fades out.
const LOAD_TIMEOUT_S: float = 0.15
const NO_TILE: Vector2i = Vector2i(2147483647, 2147483647)

@export_group("Wiring")
@export var ice_field: IceField
## Ice surface carrying thin_ice.gdshader; receives the crack and hole maps.
@export var ice_surface: GeometryInstance3D
## Authored one-shot scene placed in each new hole (shards, splash).
@export var hole_fx_scene: PackedScene

@export_group("Window")
## Tile at the window's minimum corner; tiles outside the window draw no cracks.
@export var window_origin_tile: Vector2i = Vector2i.ZERO
## Window side in tiles.
@export_range(1, 128) var window_tiles: int = 16

@export_group("Audio")
## Looping groan whose volume follows the load once the ice creaks.
@export var creak_player: AudioStreamPlayer3D
## One-shot crack; a random stream from `crack_streams` is played each step.
@export var crack_player: AudioStreamPlayer3D
@export var crack_streams: Array[AudioStream] = []
## One-shot break and splash.
@export var break_player: AudioStreamPlayer3D
## Creak loop level at full load, in dB.
@export var creak_max_db: float = -4.0

var _growth: Dictionary = {}
var _origin: Dictionary = {}
var _holes: Dictionary = {}
var _steps_played: Dictionary = {}
var _crack_image: Image
var _hole_image: Image
var _crack_texture: ImageTexture
var _hole_texture: ImageTexture
var _dirty: bool = true
var _creak_level: float = 0.0
var _creak_target: float = 0.0
var _last_load_ms: int = -100000
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 727
	_crack_image = Image.create_empty(window_tiles, window_tiles, false, Image.FORMAT_RGBAF)
	_hole_image = Image.create_empty(window_tiles, window_tiles, false, Image.FORMAT_RGBAF)
	_crack_texture = ImageTexture.create_from_image(_crack_image)
	_hole_texture = ImageTexture.create_from_image(_hole_image)
	if ice_field != null:
		ice_field.load_tile_changed.connect(_on_load_tile_changed)
		ice_field.stage_changed.connect(_on_stage_changed)
		ice_field.tile_broke.connect(_on_tile_broke)
	_bind_material()
	if creak_player != null:
		creak_player.volume_db = -80.0


func _process(delta: float) -> void:
	if Time.get_ticks_msec() - _last_load_ms > int(LOAD_TIMEOUT_S * 1000.0):
		_creak_target = 0.0
	_creak_level = move_toward(_creak_level, _creak_target, delta * 2.5)
	_update_creak()
	if _dirty:
		_upload()


## Visible crack growth of a tile, 0 none to 1 fully shattered.
func get_growth(tile: Vector2i) -> float:
	return _growth.get(tile, 0.0)


## World point where a tile's cracks started; tile centre if none yet.
func get_crack_origin(tile: Vector2i) -> Vector3:
	return _origin.get(tile, _tile_centre(tile))


func has_hole(tile: Vector2i) -> bool:
	return _holes.has(tile)


## Centre of a tile's hole on the ice surface.
func get_hole_centre(tile: Vector2i) -> Vector3:
	return _holes.get(tile, _tile_centre(tile))


## Tile whose hole contains a world point, or NO_TILE. Holes may reach neighbours.
func hole_at(point: Vector3) -> Vector2i:
	if ice_field == null:
		return NO_TILE
	var home: Vector2i = ice_field.world_to_tile(point)
	for dx: int in range(-1, 2):
		for dz: int in range(-1, 2):
			var tile: Vector2i = home + Vector2i(dx, dz)
			if _holes.has(tile) and IceHoleShape.contains(tile, _holes[tile], point):
				return tile
	return NO_TILE


func is_in_hole(point: Vector3) -> bool:
	return hole_at(point) != NO_TILE


## Raw crack map, for tests and captures: R growth, BA crack origin inside the tile.
func get_crack_image() -> Image:
	if _dirty:
		_upload()
	return _crack_image


func _on_load_tile_changed(tile: Vector2i, integrity: float, stage: IceField.Stage) -> void:
	_last_load_ms = Time.get_ticks_msec()
	var profile: IceProfile = ice_field.profile
	var base: float = maxf(0.0001, ice_field.get_base_thickness(tile))
	var fraction: float = integrity / base
	var creak_span: float = maxf(0.0001, profile.creak_below - profile.crack_below)
	_creak_target = clampf((profile.creak_below - fraction) / creak_span, 0.0, 1.0)
	if stage == IceField.Stage.CRACKING:
		_creak_target = 1.0
		_grow(tile, _growth_for(fraction, profile.crack_below))


## Holes restored from a save arrive as BROKEN without tile_broke: shown silently.
func _on_stage_changed(tile: Vector2i, stage: IceField.Stage) -> void:
	if stage == IceField.Stage.BROKEN:
		_ensure_silent_hole.call_deferred(tile)


func _on_tile_broke(tile: Vector2i, world_position: Vector3) -> void:
	var centre: Vector3 = world_position
	if ice_field.tracked_body != null:
		centre = ice_field.tracked_body.global_position
	centre.y = ice_field.global_position.y
	_open_hole(tile, centre)
	if break_player != null:
		break_player.global_position = centre
		break_player.play()
	if hole_fx_scene != null:
		var fx: Node3D = hole_fx_scene.instantiate() as Node3D
		add_child(fx)
		fx.global_position = centre
	shake_requested.emit(1.0, 0.6)
	hole_opened.emit(tile, centre)


func _ensure_silent_hole(tile: Vector2i) -> void:
	if not _holes.has(tile):
		_open_hole(tile, _tile_centre(tile))


func _open_hole(tile: Vector2i, centre: Vector3) -> void:
	if not _origin.has(tile):
		_origin[tile] = centre
	_growth[tile] = 1.0
	_holes[tile] = centre
	_dirty = true


## Maps how far below the crack threshold the ice sits to visible growth.
func _growth_for(fraction: float, crack_below: float) -> float:
	var t: float = clampf(1.0 - fraction / maxf(0.0001, crack_below), 0.0, 1.0)
	return lerpf(FIRST_CRACK_GROWTH, 1.0, t)


func _grow(tile: Vector2i, target: float) -> void:
	if not _origin.has(tile):
		var origin: Vector3 = _tile_centre(tile)
		if ice_field.tracked_body != null:
			origin = ice_field.tracked_body.global_position
		origin.y = ice_field.global_position.y
		_origin[tile] = origin
	var previous: float = _growth.get(tile, 0.0)
	if target <= previous:
		return
	_growth[tile] = target
	_dirty = true
	var step: int = int(floor((target - FIRST_CRACK_GROWTH) / CRACK_STEP)) + 1
	if step > int(_steps_played.get(tile, 0)):
		_steps_played[tile] = step
		_play_crack(_origin[tile], target)
		shake_requested.emit(0.25 + 0.35 * target, 0.25)
		crack_grew.emit(tile, target)


func _play_crack(at: Vector3, growth: float) -> void:
	if crack_player == null or crack_streams.is_empty():
		return
	crack_player.stream = crack_streams[_rng.randi_range(0, crack_streams.size() - 1)]
	crack_player.pitch_scale = _rng.randf_range(0.85, 1.15) * lerpf(1.1, 0.85, growth)
	crack_player.global_position = at
	crack_player.play()


func _update_creak() -> void:
	if creak_player == null:
		return
	if _creak_level <= 0.001:
		if creak_player.playing:
			creak_player.stop()
		return
	if not creak_player.playing:
		creak_player.play()
	creak_player.volume_db = linear_to_db(_creak_level) + creak_max_db
	creak_player.pitch_scale = lerpf(1.05, 0.8, _creak_level)
	if ice_field.tracked_body != null:
		creak_player.global_position = ice_field.tracked_body.global_position


func _bind_material() -> void:
	if ice_surface == null:
		return
	var material := ice_surface.material_override as ShaderMaterial
	if material == null:
		push_error("IceCrackPresenter: ice surface needs a ShaderMaterial override (thin_ice.gdshader)")
		return
	var size: float = ice_field.profile.tile_size_m if ice_field != null and ice_field.profile != null else 4.0
	material.set_shader_parameter(&"crack_map", _crack_texture)
	material.set_shader_parameter(&"hole_map", _hole_texture)
	material.set_shader_parameter(&"window_origin_tile", Vector2(window_origin_tile))
	material.set_shader_parameter(&"window_tiles", float(window_tiles))
	material.set_shader_parameter(&"tile_size", size)
	material.set_shader_parameter(&"hole_base_radius", IceHoleShape.BASE_RADIUS_M)


## Rewrites the window maps from the dictionaries; tiles outside the window are skipped.
func _upload() -> void:
	_dirty = false
	_crack_image.fill(Color(0, 0, 0, 0))
	_hole_image.fill(Color(0, 0, 0, 0))
	for tile: Vector2i in _growth:
		var cell: Vector2i = tile - window_origin_tile
		if cell.x < 0 or cell.y < 0 or cell.x >= window_tiles or cell.y >= window_tiles:
			continue
		var origin: Vector2 = _local_in_tile(tile, _origin.get(tile, _tile_centre(tile)))
		_crack_image.set_pixel(cell.x, cell.y, Color(_growth[tile], 0.0, origin.x, origin.y))
		if _holes.has(tile):
			var centre: Vector2 = _local_in_tile(tile, _holes[tile])
			_hole_image.set_pixel(cell.x, cell.y, Color(1.0, centre.x, centre.y, 0.0))
	_crack_texture.update(_crack_image)
	_hole_texture.update(_hole_image)


## Point position inside its tile, 0..1 per axis.
func _local_in_tile(tile: Vector2i, point: Vector3) -> Vector2:
	var size: float = ice_field.profile.tile_size_m
	return Vector2(point.x / size - float(tile.x), point.z / size - float(tile.y))


func _tile_centre(tile: Vector2i) -> Vector3:
	if ice_field == null:
		return Vector3.ZERO
	return ice_field.tile_to_world(tile)
