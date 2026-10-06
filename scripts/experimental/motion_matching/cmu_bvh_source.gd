class_name CMUBVHSource
extends Skeleton3D

## Minimal BVH source player for the Motion Matching lab.
## CMU's conversion supplies a synthetic T-pose at frame 0; datasets whose BVH
## offsets already define the bind pose can use an identity-rotation rest and
## retain frame 0 as motion. Horizontal root translation is removed from
## playback so Henry's CharacterBody remains authoritative; the raw root
## trajectory remains available for the MotionDatabase baker.

const DEFAULT_POSITION_SCALE := 0.0254 # CMU/ASF lengths are inches -> Godot meters.

var frame_count: int = 0
var frame_time: float = 0.0
var motion_frame_count: int = 0
var clip_length: float = 0.0
var source_path: String = ""
var setup_ok: bool = false
var error_message: String = ""
var position_scale: float = DEFAULT_POSITION_SCALE
var rest_frame_index: int = 0
var motion_start_frame: int = 1
var auto_detected_rest: bool = false

var _bone_names: Array[String] = []
var _parents: Array[int] = []
var _offsets: Array[Vector3] = []
var _channels: Array[PackedStringArray] = []
var _channel_starts: Array[int] = []
var _channel_count: int = 0
var _values := PackedFloat32Array()
var _tokens := PackedStringArray()
var _token_index: int = 0
var _first_motion_root_local := Vector3.ZERO
var _detect_rest_frame := false
var _include_first_frame_in_motion := false
var _use_zero_rotation_rest := false


func configure_import(
		scale_to_meters: float,
		detect_rest_frame: bool,
		include_first_frame_in_motion: bool,
		use_zero_rotation_rest: bool = false
	) -> bool:
	if setup_ok or frame_count > 0:
		return false
	position_scale = maxf(scale_to_meters, 0.000001)
	_detect_rest_frame = detect_rest_frame
	_include_first_frame_in_motion = include_first_frame_in_motion
	_use_zero_rotation_rest = use_zero_rotation_rest
	return true


func load_bvh(path: String) -> bool:
	source_path = path
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("cannot open BVH: %s" % path)
	var text := file.get_as_text()
	if text.is_empty():
		return _fail("BVH is empty: %s" % path)

	var motion_pos := text.find("MOTION")
	if motion_pos < 0:
		return _fail("BVH has no MOTION section")

	if not _parse_hierarchy(text.substr(0, motion_pos)):
		return false
	if not _parse_motion(text.substr(motion_pos)):
		return false
	if frame_count < 2:
		return _fail("BVH needs synthetic rest frame + at least one motion frame")

	rest_frame_index = 0
	if _use_zero_rotation_rest:
		rest_frame_index = -1
	elif _detect_rest_frame:
		rest_frame_index = _find_rest_frame_index()
	auto_detected_rest = _detect_rest_frame and not _use_zero_rotation_rest
	motion_start_frame = 0 if _include_first_frame_in_motion else 1
	_build_skeleton_from_rest_pose()
	motion_frame_count = frame_count - motion_start_frame
	clip_length = float(maxi(0, motion_frame_count - 1)) * frame_time
	_first_motion_root_local = _frame_local_transform(motion_start_frame, 0).origin
	setup_ok = true
	seek_seconds(0.0)
	return true


func seek_seconds(seconds: float) -> void:
	if not setup_ok or motion_frame_count <= 0:
		return
	_apply_frame(_source_frame_index(seconds))


func get_raw_root_position(seconds: float) -> Vector3:
	if frame_count < 2:
		return Vector3.ZERO
	var local := _frame_local_transform(_source_frame_index(seconds), 0).origin
	return local - _first_motion_root_local


func get_raw_root_facing(seconds: float) -> Vector3:
	if frame_count < 2:
		return Vector3.FORWARD
	var basis := _frame_local_transform(_source_frame_index(seconds), 0).basis
	var facing := basis * Vector3.FORWARD
	facing.y = 0.0
	if facing.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return facing.normalized()


func get_report() -> Dictionary:
	return {
		"setup_ok": setup_ok,
		"error": error_message,
		"source_path": source_path,
		"source_bone_count": get_bone_count(),
		"source_frame_count": frame_count,
		"motion_frame_count": motion_frame_count,
		"source_fps": 0.0 if frame_time <= 0.0 else 1.0 / frame_time,
		"clip_length_seconds": clip_length,
		"motion_frames_skipped": motion_start_frame,
		"source_bone_pose_space": "absolute_local",
		"root_playback": "in_place_xz",
		"root_facing_axis": "Godot -Z from raw BVH root basis",
		"position_scale_to_meters": position_scale,
		"rest_frame_index": rest_frame_index,
		"rest_frame_auto_detected": auto_detected_rest,
		"rest_pose_mode": "zero_rotation_offsets" if _use_zero_rotation_rest else "motion_frame",
		"motion_start_frame": motion_start_frame,
	}


func _motion_frame_index(seconds: float) -> int:
	if frame_time <= 0.0 or motion_frame_count <= 0:
		return 0
	return clampi(int(floor(maxf(seconds, 0.0) / frame_time)), 0, motion_frame_count - 1)


func _source_frame_index(seconds: float) -> int:
	return motion_start_frame + _motion_frame_index(seconds)


func _parse_hierarchy(hierarchy_text: String) -> bool:
	var normalized := hierarchy_text
	normalized = normalized.replace("\r", " ").replace("\n", " ").replace("\t", " ")
	normalized = normalized.replace("{", " { ").replace("}", " } ")
	_tokens = normalized.split(" ", false)
	_token_index = 0
	if _next_token() != "HIERARCHY":
		return _fail("BVH does not start with HIERARCHY")
	if _peek_token() != "ROOT":
		return _fail("BVH hierarchy has no ROOT")
	return _parse_joint(-1) >= 0


func _parse_joint(parent_index: int) -> int:
	var kind := _next_token()
	if kind != "ROOT" and kind != "JOINT":
		_fail("expected ROOT/JOINT, got %s" % kind)
		return -1
	if _token_index >= _tokens.size():
		_fail("missing joint name")
		return -1
	var bone_name := _next_token()
	if _next_token() != "{":
		_fail("missing { after joint %s" % bone_name)
		return -1

	var bone_index := _bone_names.size()
	_bone_names.append(bone_name)
	_parents.append(parent_index)
	_offsets.append(Vector3.ZERO)
	_channels.append(PackedStringArray())
	_channel_starts.append(_channel_count)

	while _token_index < _tokens.size():
		var token := _peek_token()
		match token:
			"OFFSET":
				_next_token()
				if _token_index + 2 >= _tokens.size():
					_fail("truncated OFFSET for %s" % bone_name)
					return -1
				_offsets[bone_index] = Vector3(
					float(_next_token()),
					float(_next_token()),
					float(_next_token())
				) * position_scale
			"CHANNELS":
				_next_token()
				var count := int(_next_token())
				var bone_channels := PackedStringArray()
				for _i in range(count):
					bone_channels.append(_next_token())
				_channels[bone_index] = bone_channels
				_channel_starts[bone_index] = _channel_count
				_channel_count += count
			"JOINT":
				if _parse_joint(bone_index) < 0:
					return -1
			"End":
				_skip_end_site()
			"}":
				_next_token()
				return bone_index
			_:
				_fail("unexpected hierarchy token %s in %s" % [token, bone_name])
				return -1

	_fail("unterminated joint %s" % bone_name)
	return -1


func _skip_end_site() -> void:
	_next_token() # End
	if _peek_token() == "Site":
		_next_token()
	if _next_token() != "{":
		return
	var depth := 1
	while _token_index < _tokens.size() and depth > 0:
		var token := _next_token()
		if token == "{":
			depth += 1
		elif token == "}":
			depth -= 1


func _parse_motion(motion_text: String) -> bool:
	var lines := motion_text.replace("\r", "").split("\n", false)
	var got_frames := false
	var got_frame_time := false
	var reading_values := false
	for raw_line in lines:
		var line := String(raw_line).strip_edges()
		if line.is_empty() or line == "MOTION":
			continue
		if not got_frames and line.begins_with("Frames:"):
			frame_count = int(line.get_slice(":", 1).strip_edges())
			got_frames = true
			continue
		if got_frames and not got_frame_time and line.begins_with("Frame Time:"):
			frame_time = float(line.get_slice(":", 1).strip_edges())
			got_frame_time = true
			reading_values = true
			continue
		if reading_values:
			for token in line.split(" ", false):
				_values.append(float(token))

	if not got_frames or not got_frame_time:
		return _fail("BVH MOTION header is incomplete")
	if frame_time <= 0.0:
		return _fail("BVH frame time is invalid")
	var expected := frame_count * _channel_count
	if _values.size() < expected:
		return _fail("BVH motion data truncated: %d < %d values" % [_values.size(), expected])
	return true


func _build_skeleton_from_rest_pose() -> void:
	for bone_index in range(_bone_names.size()):
		add_bone(_bone_names[bone_index])
	for bone_index in range(_bone_names.size()):
		set_bone_parent(bone_index, _parents[bone_index])
	for bone_index in range(_bone_names.size()):
		var rest := Transform3D(Basis.IDENTITY, _offsets[bone_index])
		if not _use_zero_rotation_rest:
			rest = _frame_local_transform(rest_frame_index, bone_index)
		set_bone_rest(bone_index, rest)
	reset_bone_poses()


func _find_rest_frame_index() -> int:
	var best_frame := 0
	var best_score := INF
	for frame_index in range(frame_count):
		var score := 0.0
		for bone_index in range(1, _bone_names.size()):
			var value_index := frame_index * _channel_count + _channel_starts[bone_index]
			var bone_channels := _channels[bone_index]
			for channel_offset in range(bone_channels.size()):
				if not String(bone_channels[channel_offset]).ends_with("rotation"):
					continue
				var angle := wrapf(float(_values[value_index + channel_offset]), -180.0, 180.0)
				score += absf(angle)
		if score < best_score:
			best_score = score
			best_frame = frame_index
	return best_frame


func _apply_frame(frame_index: int) -> void:
	for bone_index in range(get_bone_count()):
		var rest := get_bone_rest(bone_index)
		var current := _frame_local_transform(frame_index, bone_index)
		if bone_index == 0:
			# Keep the source skeleton in place. Preserve vertical bob, but remove
			# the capture's world-space X/Z travel. The raw trajectory is queried
			# separately by the baker.
			current.origin.x = rest.origin.x
			current.origin.z = rest.origin.z
			current.origin.y = rest.origin.y + (current.origin.y - _first_motion_root_local.y)
		# Skeleton3D bone poses are absolute local transforms, not rest-space
		# deltas. RetargetModifier3D performs the rest-space extraction itself.
		# Feeding rest^-1 * current here collapses child translations toward zero
		# and effectively subtracts the source rest twice during retargeting.
		set_bone_pose(bone_index, current)


func _frame_local_transform(frame_index: int, bone_index: int) -> Transform3D:
	var origin := _offsets[bone_index]
	var basis := Basis.IDENTITY
	var value_index := frame_index * _channel_count + _channel_starts[bone_index]
	var bone_channels := _channels[bone_index]
	for channel_offset in range(bone_channels.size()):
		var channel := bone_channels[channel_offset]
		var value := float(_values[value_index + channel_offset])
		match channel:
			"Xposition":
				origin.x += value * position_scale
			"Yposition":
				origin.y += value * position_scale
			"Zposition":
				origin.z += value * position_scale
			"Xrotation":
				basis = basis * Basis(Vector3.RIGHT, deg_to_rad(value))
			"Yrotation":
				basis = basis * Basis(Vector3.UP, deg_to_rad(value))
			"Zrotation":
				basis = basis * Basis(Vector3.BACK, deg_to_rad(value))
	return Transform3D(basis, origin)


func _peek_token() -> String:
	if _token_index >= _tokens.size():
		return ""
	return _tokens[_token_index]


func _next_token() -> String:
	if _token_index >= _tokens.size():
		return ""
	var token := _tokens[_token_index]
	_token_index += 1
	return token


func _fail(message: String) -> bool:
	error_message = message
	setup_ok = false
	push_error("CMUBVHSource: %s" % message)
	return false
