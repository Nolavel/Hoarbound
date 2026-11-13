class_name InputTape
extends RefCounted

## A recorded run: input actions and camera look per physics frame, plus where it started.
## Versioned JSON, so a tester's route can be replayed after every change.

const VERSION: int = 1
## Actions a tape never carries: menus, the recorder's own key and developer cheats.
const SKIPPED_PREFIXES: Array[String] = ["ui_", "dev_"]
const SKIPPED_ACTIONS: Array[StringName] = [&"pause", &"toggle_dev_map", &"toggle_hlod_tiers", &"report_bundle"]

var scene: String = ""
var physics_fps: int = 60
var build: String = ""
var start_transform: Transform3D = Transform3D.IDENTITY
var start_look: Vector2 = Vector2.ZERO
## Save payload of the world when recording started (weather, snow, clock, inventory...).
var world: Dictionary = {}
## Global RNG seed set when recording started, so random rolls after it repeat.
var rng_seed: int = 0
## [frame, action, pressed, strength]
var events: Array = []
## [frame, yaw, pitch_deg]
var looks: Array = []


## Actions worth recording: gameplay ones from the input map.
static func tracked_actions() -> Array[StringName]:
	var out: Array[StringName] = []
	for action: StringName in InputMap.get_actions():
		var name: String = String(action)
		if SKIPPED_ACTIONS.has(action) or SKIPPED_PREFIXES.any(func(p: String) -> bool: return name.begins_with(p)):
			continue
		out.append(action)
	return out


## Last frame anything happens on.
func length_frames() -> int:
	var last: int = 0
	if not events.is_empty():
		last = maxi(last, int(events[-1][0]))
	if not looks.is_empty():
		last = maxi(last, int(looks[-1][0]))
	return last


func to_dict() -> Dictionary:
	var o: Vector3 = start_transform.origin
	return {
		"version": VERSION, "scene": scene, "physics_fps": physics_fps, "build": build,
		"start": {"origin": [o.x, o.y, o.z], "yaw": start_transform.basis.get_euler().y, "look": [start_look.x, start_look.y]},
		"world": world, "rng_seed": rng_seed,
		"events": events, "looks": looks,
	}


static func from_dict(data: Dictionary) -> InputTape:
	if int(data.get("version", 0)) != VERSION:
		push_error("InputTape: unsupported version %s" % str(data.get("version")))
		return null
	var tape := InputTape.new()
	tape.scene = String(data.get("scene", ""))
	tape.physics_fps = int(data.get("physics_fps", 60))
	tape.build = String(data.get("build", ""))
	var start: Dictionary = data.get("start", {})
	var o: Array = start.get("origin", [0, 0, 0])
	tape.start_transform = Transform3D(Basis(Vector3.UP, float(start.get("yaw", 0.0))), Vector3(o[0], o[1], o[2]))
	var look: Array = start.get("look", [0, 0])
	tape.start_look = Vector2(look[0], look[1])
	tape.world = data.get("world", {})
	tape.rng_seed = int(data.get("rng_seed", 0))
	tape.events = data.get("events", [])
	tape.looks = data.get("looks", [])
	return tape


func save(path: String) -> Error:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(to_dict()))
	return OK


static func load_file(path: String) -> InputTape:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return from_dict(parsed) if parsed is Dictionary else null
