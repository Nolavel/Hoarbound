class_name SoundSystemService
extends Node

## Autoload `SoundSystem`: plays SoundEvents from pooled voices, runs
## parameter-driven SoundLayers, owns the bus layout and the interior filter.

const BUSES: Array[StringName] = [&"Music", &"SFX", &"Ambience", &"UI", &"Voice"]
## Buses the interior low-pass muffles: the world, not the menu.
const WORLD_BUSES: Array[StringName] = [&"SFX", &"Ambience"]
const PARAM_INTERIOR: StringName = &"interior"
const OPEN_CUTOFF_HZ: float = 20000.0
const INVALID: int = -1

@export var pool_size_flat: int = 16
@export var pool_size_spatial: int = 32
## Cutoff at interior = 1.0: a closed room hears the storm through the walls.
@export var interior_cutoff_hz: float = 900.0
@export var interior_smoothing_s: float = 0.6

var _rng := RandomNumberGenerator.new()
var _params: Dictionary = {}
var _flat_pool: Array[AudioStreamPlayer] = []
var _spatial_pool: Array[AudioStreamPlayer3D] = []
## handle -> {player, event, started_ms}
var _voices: Dictionary = {}
## handle -> {player, layer, gain}
var _layers: Dictionary = {}
var _last_play_ms: Dictionary = {}
var _next_handle: int = 1
var _interior: float = 0.0
var _filters: Array[AudioEffectLowPassFilter] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_ensure_buses()
	_set_interior_cutoff(0.0)


func _process(delta: float) -> void:
	_update_interior(delta)
	_update_layers(delta)


## Plays one variation of `event`; returns a handle, or INVALID when dropped.
## Callers may shade one play (a deeper step) with a gain and a pitch factor.
func play(event: SoundEvent, at: Vector3 = Vector3.INF, gain_db: float = 0.0, pitch_scale: float = 1.0) -> int:
	if event == null:
		return INVALID
	var now: int = Time.get_ticks_msec()
	if event.cooldown_s > 0.0 and _last_play_ms.has(event):
		if now - int(_last_play_ms[event]) < int(event.cooldown_s * 1000.0):
			return INVALID
	var stream: AudioStream = event.next_stream(_rng)
	if stream == null:
		return INVALID
	_enforce_instance_limit(event)
	var spatial: bool = event.spatial and at != Vector3.INF
	var player: Node = _take_spatial() if spatial else _take_flat()
	if player == null:
		return INVALID
	_last_play_ms[event] = now
	player.set(&"stream", stream)
	player.set(&"bus", event.bus)
	player.set(&"volume_db", event.roll_volume_db(_rng) + gain_db)
	player.set(&"pitch_scale", event.roll_pitch(_rng) * maxf(pitch_scale, 0.05))
	if spatial:
		var p3d := player as AudioStreamPlayer3D
		p3d.unit_size = event.unit_size
		p3d.max_distance = event.max_distance_m
		p3d.global_position = at
	if spatial:
		(player as AudioStreamPlayer3D).play()
	else:
		(player as AudioStreamPlayer).play()
	var handle: int = _new_handle()
	_voices[handle] = {"player": player, "event": event, "started_ms": now}
	return handle


func stop(handle: int) -> void:
	if _voices.has(handle):
		_release_voice(handle)
	elif _layers.has(handle):
		var entry: Dictionary = _layers[handle]
		(entry["player"] as AudioStreamPlayer).queue_free()
		_layers.erase(handle)


func is_playing(handle: int) -> bool:
	return _voices.has(handle) or _layers.has(handle)


## Live voices of one event; limits and tests read this.
func count_voices(event: SoundEvent) -> int:
	var count: int = 0
	for entry: Dictionary in _voices.values():
		if entry["event"] == event:
			count += 1
	return count


## Starts a looping parameter-driven bed; stop it with stop(handle).
func start_layer(layer: SoundLayer) -> int:
	if layer == null or layer.stream == null:
		return INVALID
	var player := AudioStreamPlayer.new()
	player.stream = layer.stream
	player.bus = layer.bus
	add_child(player)
	var gain: float = layer.gain_at(get_parameter(layer.parameter))
	_apply_layer(player, layer, gain)
	player.play()
	var handle: int = _new_handle()
	_layers[handle] = {"player": player, "layer": layer, "gain": gain}
	return handle


## Smoothed gain a running layer is at now, 0..1.
func get_layer_gain(handle: int) -> float:
	return float(_layers[handle]["gain"]) if _layers.has(handle) else 0.0


func set_parameter(name: StringName, value: float) -> void:
	_params[name] = value


func get_parameter(name: StringName, fallback: float = 0.0) -> float:
	return float(_params.get(name, fallback))


## Linear 0..1 volume for a settings slider.
func set_bus_volume(bus: StringName, linear: float) -> void:
	var index: int = AudioServer.get_bus_index(bus)
	if index >= 0:
		AudioServer.set_bus_volume_db(index, linear_to_db(clampf(linear, 0.0, 1.0)))


func get_interior_cutoff_hz() -> float:
	return _filters[0].cutoff_hz if not _filters.is_empty() else OPEN_CUTOFF_HZ


func _ensure_buses() -> void:
	for bus: StringName in BUSES:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, &"Master")
	for bus: StringName in WORLD_BUSES:
		var index: int = AudioServer.get_bus_index(bus)
		var filter: AudioEffectLowPassFilter = null
		for i: int in range(AudioServer.get_bus_effect_count(index)):
			if AudioServer.get_bus_effect(index, i) is AudioEffectLowPassFilter:
				filter = AudioServer.get_bus_effect(index, i) as AudioEffectLowPassFilter
		if filter == null:
			filter = AudioEffectLowPassFilter.new()
			AudioServer.add_bus_effect(index, filter, 0)
		_filters.append(filter)


func _update_interior(delta: float) -> void:
	var target: float = clampf(get_parameter(PARAM_INTERIOR), 0.0, 1.0)
	if is_equal_approx(_interior, target):
		return
	_interior = move_toward(_interior, target, delta / maxf(interior_smoothing_s, 0.001))
	_set_interior_cutoff(_interior)


## Exponential sweep: the ear hears cutoff in octaves, not hertz.
func _set_interior_cutoff(amount: float) -> void:
	var hz: float = exp(lerpf(log(OPEN_CUTOFF_HZ), log(interior_cutoff_hz), amount))
	for filter: AudioEffectLowPassFilter in _filters:
		filter.cutoff_hz = hz


func _update_layers(delta: float) -> void:
	for entry: Dictionary in _layers.values():
		var layer: SoundLayer = entry["layer"]
		var target: float = layer.gain_at(get_parameter(layer.parameter))
		var step: float = delta / maxf(layer.smoothing_s, 0.001)
		entry["gain"] = move_toward(float(entry["gain"]), target, step)
		_apply_layer(entry["player"], layer, float(entry["gain"]))


func _apply_layer(player: AudioStreamPlayer, layer: SoundLayer, gain: float) -> void:
	player.volume_db = layer.volume_db + linear_to_db(maxf(gain, 0.0001))
	player.pitch_scale = layer.pitch_at(get_parameter(layer.parameter))


func _enforce_instance_limit(event: SoundEvent) -> void:
	while count_voices(event) >= event.max_instances:
		var oldest: int = INVALID
		var oldest_ms: int = 0
		for handle: int in _voices:
			var entry: Dictionary = _voices[handle]
			if entry["event"] == event and (oldest == INVALID or int(entry["started_ms"]) < oldest_ms):
				oldest = handle
				oldest_ms = int(entry["started_ms"])
		_release_voice(oldest)


func _take_flat() -> AudioStreamPlayer:
	for player: AudioStreamPlayer in _flat_pool:
		if not _is_busy(player):
			return player
	if _flat_pool.size() >= pool_size_flat:
		return null
	var player := AudioStreamPlayer.new()
	player.finished.connect(_on_voice_finished.bind(player))
	add_child(player)
	_flat_pool.append(player)
	return player


func _take_spatial() -> AudioStreamPlayer3D:
	for player: AudioStreamPlayer3D in _spatial_pool:
		if not _is_busy(player):
			return player
	if _spatial_pool.size() >= pool_size_spatial:
		return null
	var player := AudioStreamPlayer3D.new()
	player.finished.connect(_on_voice_finished.bind(player))
	add_child(player)
	_spatial_pool.append(player)
	return player


func _is_busy(player: Node) -> bool:
	for entry: Dictionary in _voices.values():
		if entry["player"] == player:
			return true
	return false


func _release_voice(handle: int) -> void:
	var player: Node = _voices[handle]["player"]
	if player is AudioStreamPlayer3D:
		(player as AudioStreamPlayer3D).stop()
	else:
		(player as AudioStreamPlayer).stop()
	_voices.erase(handle)


func _on_voice_finished(player: Node) -> void:
	for handle: int in _voices.keys():
		if _voices[handle]["player"] == player:
			_voices.erase(handle)
			return


func _new_handle() -> int:
	var handle: int = _next_handle
	_next_handle += 1
	return handle
