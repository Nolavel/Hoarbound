class_name LutBlendCache
extends RefCounted

## In-between LUTs for every profile pair, baked on worker threads (cf. UE4 CombineLUTs): a grade
## crossfade stays on the Environment's own post-tonemap LUT path instead of a second screen pass.

## In-between steps per pair; step 0 and STEPS are the source LUTs themselves.
const STEPS: int = 16

var _ids: Array[StringName] = []
var _sources: Array[PackedByteArray] = []
var _size: Vector3i = Vector3i.ZERO
var _format: Image.Format = Image.FORMAT_RGB8
var _pairs: Array[Vector2i] = []
var _baked: Dictionary = {}
var _mutex: Mutex = Mutex.new()
var _task: int = -1
var _done: bool = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)


## Registers a profile LUT; skipped when its texels cannot be read back or differ in layout.
func add_profile(profile_id: StringName, lut: Texture3D) -> bool:
	if lut == null:
		return false
	var slices: Array[Image] = lut.get_data()
	if slices.size() > lut.get_depth():
		slices.resize(lut.get_depth())
	return add_slices(profile_id, slices)


## Registers a profile from its Z slices (uncompressed RGB8/RGBA8, same layout as the others).
func add_slices(profile_id: StringName, slices: Array[Image]) -> bool:
	if slices.is_empty() or not _pairs.is_empty() or _ids.has(profile_id):
		return false
	var size := Vector3i(slices[0].get_width(), slices[0].get_height(), slices.size())
	var format: Image.Format = slices[0].get_format()
	if not format in [Image.FORMAT_RGB8, Image.FORMAT_RGBA8]:
		return false
	if not _ids.is_empty() and (size != _size or format != _format):
		return false
	var bytes := PackedByteArray()
	for slice: Image in slices:
		if slice.get_width() != size.x or slice.get_height() != size.y or slice.get_format() != format:
			return false
		bytes.append_array(slice.get_data())
	_size = size
	_format = format
	_ids.append(profile_id)
	_sources.append(bytes)
	return true


func start_bake() -> void:
	if not _pairs.is_empty() or _ids.size() < 2:
		return
	for a: int in _ids.size():
		for b: int in range(a + 1, _ids.size()):
			_pairs.append(Vector2i(a, b))
	_task = WorkerThreadPool.add_group_task(_bake_step, _pairs.size() * (STEPS - 1), -1, false, "LUT blend bake")


func wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
		_done = true


func is_baked() -> bool:
	if _task >= 0 and WorkerThreadPool.is_group_task_completed(_task):
		wait()
	return _done


## Slices of the LUT `step`/STEPS of the way from one profile to another; empty when not baked yet.
func get_slices(from_id: StringName, to_id: StringName, step: int) -> Array[Image]:
	var out: Array[Image] = []
	var a: int = _ids.find(from_id)
	var b: int = _ids.find(to_id)
	if a < 0 or b < 0 or a == b or step <= 0 or step >= STEPS:
		return out
	if a > b:
		var swap: int = a
		a = b
		b = swap
		step = STEPS - step
	_mutex.lock()
	var bytes: PackedByteArray = _baked.get(Vector3i(a, b, step), PackedByteArray())
	_mutex.unlock()
	if bytes.is_empty():
		return out
	var slice_size: int = bytes.size() / _size.z
	for z: int in _size.z:
		out.append(Image.create_from_data(_size.x, _size.y, false, _format, bytes.slice(z * slice_size, (z + 1) * slice_size)))
	return out


## Per-texel lerp in 8.8 fixed point.
static func lerp_bytes(a: PackedByteArray, b: PackedByteArray, t: float) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(a.size())
	var w: int = clampi(roundi(t * 256.0), 0, 256)
	for i: int in a.size():
		out[i] = (a[i] * (256 - w) + b[i] * w + 128) >> 8
	return out


func _bake_step(index: int) -> void:
	var pair: Vector2i = _pairs[index / (STEPS - 1)]
	var step: int = index % (STEPS - 1) + 1
	var bytes: PackedByteArray = lerp_bytes(_sources[pair.x], _sources[pair.y], float(step) / float(STEPS))
	_mutex.lock()
	_baked[Vector3i(pair.x, pair.y, step)] = bytes
	_mutex.unlock()
