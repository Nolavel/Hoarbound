class_name BVHClip
extends RefCounted

## Parsed BVH motion with forward kinematics in source model space (meters).
## Pure data: no scene tree, no Skeleton3D. Unit scale comes from the profile.

var source_path: String = ""
var frame_count: int = 0
var frame_time: float = 0.0
var units_to_meters: float = 1.0
var error_message: String = ""

var bone_names: PackedStringArray = PackedStringArray()
var parents: PackedInt32Array = PackedInt32Array()
var offsets: Array[Vector3] = []

var _channels: Array[PackedStringArray] = []
var _channel_starts: PackedInt32Array = PackedInt32Array()
var _channel_count: int = 0
var _values: PackedFloat32Array = PackedFloat32Array()
var _tokens: PackedStringArray = PackedStringArray()
var _token_index: int = 0
var _in_end_site: bool = false


func load_file(path: String, scale_to_meters: float) -> bool:
	source_path = path
	units_to_meters = maxf(scale_to_meters, 0.000001)
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return _fail("cannot read BVH: %s" % path)
	var motion_pos := text.find("MOTION")
	if motion_pos < 0:
		return _fail("BVH has no MOTION section")
	if not _parse_hierarchy(text.substr(0, motion_pos)):
		return false
	if not _parse_motion(text.substr(motion_pos)):
		return false
	return frame_count > 1 or _fail("BVH has fewer than two frames")


func find_bone(bone_name: String) -> int:
	return bone_names.find(bone_name)


func get_bone_count() -> int:
	return bone_names.size()


func get_duration(first_frame: int = 0) -> float:
	return float(maxi(0, frame_count - 1 - first_frame)) * frame_time


func frame_at_time(seconds: float, first_frame: int = 0) -> int:
	if frame_time <= 0.0:
		return first_frame
	return clampi(first_frame + int(round(maxf(seconds, 0.0) / frame_time)), first_frame, frame_count - 1)


## Local joint transform of one frame; frame -1 is the zero-rotation offset pose.
func local_transform(frame_index: int, bone_index: int) -> Transform3D:
	var origin := offsets[bone_index]
	var basis := Basis.IDENTITY
	if frame_index < 0:
		return Transform3D(basis, origin)
	var value_index := frame_index * _channel_count + _channel_starts[bone_index]
	var bone_channels := _channels[bone_index]
	for channel_offset in range(bone_channels.size()):
		var value := _values[value_index + channel_offset]
		match bone_channels[channel_offset]:
			"Xposition":
				origin.x += value * units_to_meters
			"Yposition":
				origin.y += value * units_to_meters
			"Zposition":
				origin.z += value * units_to_meters
			"Xrotation":
				basis = basis * Basis(Vector3.RIGHT, deg_to_rad(value))
			"Yrotation":
				basis = basis * Basis(Vector3.UP, deg_to_rad(value))
			"Zrotation":
				basis = basis * Basis(Vector3.BACK, deg_to_rad(value))
	return Transform3D(basis, origin)


## Global (model-space) transforms of every joint for one frame.
func global_transforms(frame_index: int) -> Array[Transform3D]:
	var result: Array[Transform3D] = []
	result.resize(bone_names.size())
	for bone_index in range(bone_names.size()):
		var local := local_transform(frame_index, bone_index)
		var parent := parents[bone_index]
		result[bone_index] = local if parent < 0 else result[parent] * local
	return result


func _parse_hierarchy(hierarchy_text: String) -> bool:
	var normalized := hierarchy_text.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	normalized = normalized.replace("{", " { ").replace("}", " } ")
	_tokens = normalized.split(" ", false)
	_token_index = 0
	if _next_token() != "HIERARCHY" or _peek_token() != "ROOT":
		return _fail("BVH hierarchy is malformed")
	var stack: Array[int] = []
	while _token_index < _tokens.size():
		var token := _next_token()
		match token:
			"ROOT", "JOINT":
				bone_names.append(_next_token())
				parents.append(stack.back() if not stack.is_empty() else -1)
				offsets.append(Vector3.ZERO)
				_channels.append(PackedStringArray())
				_channel_starts.append(_channel_count)
				stack.append(bone_names.size() - 1)
				_next_token() # {
			"OFFSET":
				var offset := Vector3(float(_next_token()), float(_next_token()), float(_next_token()))
				if not _in_end_site:
					offsets[stack.back()] = offset * units_to_meters
			"CHANNELS":
				var count := int(_next_token())
				var bone_channels := PackedStringArray()
				for _i in range(count):
					bone_channels.append(_next_token())
				_channels[stack.back()] = bone_channels
				_channel_starts[stack.back()] = _channel_count
				_channel_count += count
			"End":
				_in_end_site = true
				_next_token() # Site
				_next_token() # {
			"}":
				if _in_end_site:
					_in_end_site = false
				elif not stack.is_empty():
					stack.pop_back()
	return not bone_names.is_empty() or _fail("BVH has no joints")


func _parse_motion(motion_text: String) -> bool:
	var lines := motion_text.replace("\r", "").split("\n", false)
	var reading_values := false
	for raw_line in lines:
		var line := String(raw_line).strip_edges()
		if line.is_empty() or line == "MOTION":
			continue
		if line.begins_with("Frames:"):
			frame_count = int(line.get_slice(":", 1).strip_edges())
		elif line.begins_with("Frame Time:"):
			frame_time = float(line.get_slice(":", 1).strip_edges())
			reading_values = true
		elif reading_values:
			for token in line.split(" ", false):
				_values.append(float(token))
	if frame_time <= 0.0:
		return _fail("BVH frame time is invalid")
	if _values.size() < frame_count * _channel_count:
		return _fail("BVH motion data truncated: %d < %d" % [_values.size(), frame_count * _channel_count])
	return true


func _peek_token() -> String:
	return "" if _token_index >= _tokens.size() else _tokens[_token_index]


func _next_token() -> String:
	if _token_index >= _tokens.size():
		return ""
	_token_index += 1
	return _tokens[_token_index - 1]


func _fail(message: String) -> bool:
	error_message = message
	push_error("BVHClip: %s" % message)
	return false
