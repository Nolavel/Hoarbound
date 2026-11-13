extends Node3D

## One-shot hole dressing: shards settle and bob in the water, the splash fires once.
## Layout lives in ice_hole_fx.tscn so it is tuned in the editor, not here.

## Seconds over which the shards' bobbing dies down.
@export var settle_seconds: float = 6.0
## Peak bob height in metres right after the break.
@export var bob_height_m: float = 0.06
@export var shards: Array[Node3D] = []
@export var splash: GPUParticles3D

var _rest: Array[Transform3D] = []
var _age: float = 0.0


func _ready() -> void:
	for shard: Node3D in shards:
		_rest.append(shard.transform)
	if splash != null:
		splash.restart()
		splash.emitting = true


func _process(delta: float) -> void:
	_age += delta
	var calm: float = exp(-_age / maxf(0.1, settle_seconds * 0.35))
	for i: int in range(shards.size()):
		var phase: float = _age * (2.2 + 0.37 * float(i)) + float(i) * 1.7
		var shard: Node3D = shards[i]
		shard.transform = _rest[i]
		shard.position.y += sin(phase) * bob_height_m * calm
		shard.rotate_object_local(Vector3.RIGHT, sin(phase * 0.8) * 0.12 * calm)
	if _age > settle_seconds:
		set_process(false)
