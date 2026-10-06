class_name MotionMatchingDatabasePlaybackController
extends RefCounted

## Multi-clip issue #202 playback.
## Search returns a sample from one merged MotionDatabase; playback applies the
## canonical post-retarget UAL pose stored in that row. Original BVHs are not
## consulted at runtime, so switches can cross source captures safely.

const FUTURE_HORIZONS := [0.2, 0.5, 0.8]
const MATCH_INTERVAL := 0.10
const SWITCH_COOLDOWN := 0.28
const CROSSFADE_DURATION := 0.16
const SWITCH_MIN_ABSOLUTE := 1.0
const SWITCH_MIN_RATIO := 0.12
const SAME_CLIP_NEIGHBORHOOD_SECONDS := 1.50
const DESIRED_COLOR := Color(0.18, 1.0, 0.30, 1.0)
const SELECTED_COLOR := Color(0.15, 0.55, 1.0, 1.0)
const TRAJECTORY_Y := -0.92
const SELECTED_Y_OFFSET := 0.035
const RIBBON_HALF_WIDTH := 0.045
const ARROW_LENGTH := 0.26
const ARROW_HALF_WIDTH := 0.14

var _lab: CMUUALRetargetLab
var _database: MotionDatabase
var _tree: SceneTree
var _skeleton: Skeleton3D
var _readout: Label3D

var _builder := MotionRuntimeQueryBuilder.new()
var _matcher := MotionMatcher.new()

var _pose_target_indices: PackedInt32Array = PackedInt32Array()
var _previous_pose: Dictionary = {}
var _current_sample := -1
var _sample_accumulator := 0.0
var _cooldown_remaining := 0.0
var _match_accumulator := 0.0
var _last_query_label := ""
var _last_best: Dictionary = {}
var _last_current_cost: Dictionary = {}
var _last_switched := false
var _last_gate_reason := "START"

var _blend_active := false
var _blend_elapsed := 0.0
var _blend_from_rotations: Array[Quaternion] = []

var _desired_mesh_instance: MeshInstance3D
var _selected_mesh_instance: MeshInstance3D
var _desired_material: StandardMaterial3D
var _selected_material: StandardMaterial3D

var _match_evaluations := 0
var _continuity_blocks := 0
var _cross_clip_switches := 0
var _switch_events: Array[Dictionary] = []


func setup(lab: CMUUALRetargetLab, database: MotionDatabase, initial_sample: int = 0) -> bool:
	if lab == null or database == null or not database.is_consistent():
		return false
	if database.pose_bone_names.is_empty() or database.get_sample_count() <= 0:
		push_error("MotionMatchingDatabasePlaybackController: canonical pose rows are missing.")
		return false

	_lab = lab
	_database = database
	_tree = lab.get_tree()
	_skeleton = lab.get_target_skeleton()
	_readout = lab.get_node_or_null(^"Debug/Readout") as Label3D
	if _tree == null or _skeleton == null:
		return false

	_lab.set_retarget_active(false)
	_pose_target_indices.resize(_database.pose_bone_names.size())
	for pose_index in range(_database.pose_bone_names.size()):
		var target_index := _skeleton.find_bone(_database.pose_bone_names[pose_index])
		if target_index < 0:
			push_error("MotionMatchingDatabasePlaybackController: Henry is missing pose bone %s." % _database.pose_bone_names[pose_index])
			return false
		_pose_target_indices[pose_index] = target_index

	_current_sample = clampi(initial_sample, 0, _database.get_sample_count() - 1)
	_apply_database_pose()
	await _tree.process_frame
	_previous_pose = _builder.capture_pose(_skeleton)
	_match_accumulator = MATCH_INTERVAL

	if _readout != null:
		_readout.position = Vector3(0.0, 1.62, 0.0)
		_readout.font_size = 21
		_readout.outline_size = 6
	_prepare_debug_meshes()
	_update_debug(Vector2.ZERO, "START", {}, {}, false)
	return not _previous_pose.is_empty()


func step(delta: float, desired_local_velocity: Vector2, query_label: String) -> Dictionary:
	if _database == null or _skeleton == null or _current_sample < 0:
		return {}

	var dt := maxf(delta, 0.000001)
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - dt)
	_advance_natural_playback(dt)
	if _blend_active:
		_blend_elapsed += dt
	_apply_database_pose()
	await _tree.process_frame

	var current_pose := _builder.capture_pose(_skeleton)
	if current_pose.is_empty():
		return {}
	if _previous_pose.is_empty():
		_previous_pose = current_pose.duplicate(true)

	var label_changed := query_label != _last_query_label
	_last_query_label = query_label
	if label_changed:
		_match_accumulator = MATCH_INTERVAL
	else:
		_match_accumulator += dt

	_last_switched = false
	if _match_accumulator >= MATCH_INTERVAL:
		_match_accumulator = fposmod(_match_accumulator, MATCH_INTERVAL)
		var query := _build_live_query(_previous_pose, current_pose, dt, desired_local_velocity)
		if query.size() == _database.feature_count:
			_evaluate_and_maybe_switch(query, desired_local_velocity, query_label)
			if _last_switched:
				_apply_database_pose()
				await _tree.process_frame
				current_pose = _builder.capture_pose(_skeleton)

	_previous_pose = current_pose.duplicate(true)
	_update_debug(desired_local_velocity, query_label, _last_current_cost, _last_best, _last_switched)
	return get_snapshot()


func get_snapshot() -> Dictionary:
	return {
		"current_sample": _current_sample,
		"current_clip": _database.get_sample_clip_name(_current_sample) if _database != null else "",
		"current_role": _database.get_sample_role(_current_sample) if _database != null else "",
		"playback_time": _database.get_sample_time(_current_sample) if _database != null else 0.0,
		"cooldown_remaining": _cooldown_remaining,
		"blend_active": _blend_active,
		"blend_alpha": 1.0 if not _blend_active else clampf(_blend_elapsed / CROSSFADE_DURATION, 0.0, 1.0),
		"last_query_label": _last_query_label,
		"last_switched": _last_switched,
		"gate_reason": _last_gate_reason,
		"last_best": _last_best.duplicate(true),
		"current_cost": _last_current_cost.duplicate(true),
	}


func get_report() -> Dictionary:
	return {
		"mode": "merged_database_canonical_pose_playback",
		"search_interval_seconds": MATCH_INTERVAL,
		"switch_cooldown_seconds": SWITCH_COOLDOWN,
		"crossfade_seconds": CROSSFADE_DURATION,
		"switch_min_absolute_improvement": SWITCH_MIN_ABSOLUTE,
		"switch_min_ratio": SWITCH_MIN_RATIO,
		"same_clip_neighborhood_seconds": SAME_CLIP_NEIGHBORHOOD_SECONDS,
		"match_evaluations": _match_evaluations,
		"continuity_blocks": _continuity_blocks,
		"switch_count": _switch_events.size(),
		"cross_clip_switch_count": _cross_clip_switches,
		"switch_events": _switch_events.duplicate(true),
		"last_snapshot": get_snapshot(),
		"debug": {
			"desired_trajectory": "green",
			"selected_best_trajectory": "blue",
			"readout": "CURRENT clip/role/sample + BEST clip + costs + gate",
		},
	}


func _advance_natural_playback(delta: float) -> void:
	_sample_accumulator += delta * _database.sample_rate_hz
	while _sample_accumulator >= 1.0:
		_sample_accumulator -= 1.0
		var next_sample := _database.get_next_sample_in_clip(_current_sample)
		if next_sample == _current_sample:
			_sample_accumulator = 0.0
			break
		_current_sample = next_sample


func _build_live_query(
		previous_pose: Dictionary,
		current_pose: Dictionary,
		delta: float,
		desired_local_velocity: Vector2
	) -> PackedFloat32Array:
	var row := _database.get_feature_row(_current_sample)
	if row.size() < 3:
		return PackedFloat32Array()
	var facing := _database.get_sample_root_facing(_current_sample)
	var right := Vector2(-facing.y, facing.x)
	var local_velocity := Vector2(row[0], row[1])
	var root_velocity_xz := right * local_velocity.x + facing * local_velocity.y
	var root_velocity_world := Vector3(root_velocity_xz.x, 0.0, root_velocity_xz.y)

	return _builder.build_query(
		previous_pose,
		current_pose,
		delta,
		root_velocity_world,
		row[2],
		facing,
		desired_local_velocity,
		Vector2(0.0, 1.0)
	)


func _evaluate_and_maybe_switch(
		query: PackedFloat32Array,
		desired_local_velocity: Vector2,
		query_label: String
	) -> void:
	_match_evaluations += 1
	_last_current_cost = _matcher.score_sample(_database, _current_sample, query)
	_last_best = _matcher.find_best(_database, query)
	if _last_best.is_empty() or _last_current_cost.is_empty():
		_last_gate_reason = "NO MATCH"
		return

	var current_total := float(_last_current_cost["total"])
	var best_total := float(_last_best["total_cost"])
	var improvement := current_total - best_total
	var required_improvement := maxf(SWITCH_MIN_ABSOLUTE, current_total * SWITCH_MIN_RATIO)
	var best_sample := int(_last_best["sample_index"])
	var best_time := float(_last_best["time"])
	var current_clip := _database.get_sample_clip_name(_current_sample)
	var best_clip := String(_last_best["clip"])
	var same_clip := best_clip == current_clip
	var separated_sample: bool = best_sample < _current_sample - 2 or best_sample > _current_sample + 2
	var local_reseek := same_clip and absf(_database.get_sample_time(_current_sample) - best_time) < SAME_CLIP_NEIGHBORHOOD_SECONDS

	_last_gate_reason = "HOLD"
	if local_reseek:
		_last_gate_reason = "CONTINUE"
		_continuity_blocks += 1
	elif _cooldown_remaining > 0.0:
		_last_gate_reason = "COOLDOWN"
	elif not separated_sample:
		_last_gate_reason = "CONTINUE"

	var should_switch := (
		_cooldown_remaining <= 0.0
		and separated_sample
		and not local_reseek
		and improvement > required_improvement
	)
	if not should_switch:
		return

	var from_sample := _current_sample
	var from_time := _database.get_sample_time(from_sample)
	var from_clip := current_clip
	_begin_crossfade()
	_current_sample = best_sample
	_sample_accumulator = 0.0
	_cooldown_remaining = SWITCH_COOLDOWN
	_last_switched = true
	_last_gate_reason = "SWITCH"
	if from_clip != best_clip:
		_cross_clip_switches += 1

	var event := {
		"query": query_label,
		"from_sample": from_sample,
		"from_clip": from_clip,
		"from_time": from_time,
		"to_sample": best_sample,
		"to_clip": best_clip,
		"to_role": _database.get_sample_role(best_sample),
		"to_time": best_time,
		"current_cost": current_total,
		"best_cost": best_total,
		"improvement": improvement,
		"required_improvement": required_improvement,
		"desired_velocity": [desired_local_velocity.x, desired_local_velocity.y],
	}
	_switch_events.append(event)
	print("[MM_MULTI_SWITCH] %-13s %s:%d@%.3f -> %s:%d@%.3f role=%s improvement=%.3f" % [
		query_label,
		from_clip,
		from_sample,
		from_time,
		best_clip,
		best_sample,
		best_time,
		_database.get_sample_role(best_sample),
		improvement,
	])


func _begin_crossfade() -> void:
	_blend_from_rotations.clear()
	_blend_from_rotations.resize(_pose_target_indices.size())
	for pose_index in range(_pose_target_indices.size()):
		_blend_from_rotations[pose_index] = _skeleton.get_bone_pose_rotation(_pose_target_indices[pose_index])
	_blend_elapsed = 0.0
	_blend_active = true


func _apply_database_pose() -> void:
	if _current_sample < 0:
		return
	var alpha := 1.0
	if _blend_active:
		alpha = clampf(_blend_elapsed / CROSSFADE_DURATION, 0.0, 1.0)
	for pose_index in range(_pose_target_indices.size()):
		var target_rotation := _database.get_pose_rotation(_current_sample, pose_index)
		if _blend_active and _blend_from_rotations.size() == _pose_target_indices.size():
			target_rotation = _blend_from_rotations[pose_index].slerp(target_rotation, alpha)
		_skeleton.set_bone_pose_rotation(_pose_target_indices[pose_index], target_rotation)
	if _blend_active and alpha >= 0.999:
		_blend_active = false
		_blend_from_rotations.clear()


func _prepare_debug_meshes() -> void:
	var debug_root := _lab.get_node_or_null(^"Debug") as Node3D
	if debug_root == null:
		return

	_desired_mesh_instance = MeshInstance3D.new()
	_desired_mesh_instance.name = "DesiredTrajectory"
	debug_root.add_child(_desired_mesh_instance)
	_desired_mesh_instance.mesh = ImmediateMesh.new()

	_selected_mesh_instance = MeshInstance3D.new()
	_selected_mesh_instance.name = "SelectedTrajectory"
	debug_root.add_child(_selected_mesh_instance)
	_selected_mesh_instance.mesh = ImmediateMesh.new()

	_desired_material = _make_debug_material(DESIRED_COLOR)
	_selected_material = _make_debug_material(SELECTED_COLOR)


func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	material.albedo_color = color
	return material


func _update_debug(
		desired_local_velocity: Vector2,
		query_label: String,
		current_cost: Dictionary,
		best: Dictionary,
		switched: bool
	) -> void:
	if _readout != null:
		var current_total := -1.0 if current_cost.is_empty() else float(current_cost["total"])
		var best_total := -1.0 if best.is_empty() else float(best["total_cost"])
		var best_sample := -1 if best.is_empty() else int(best["sample_index"])
		var best_time := 0.0 if best.is_empty() else float(best["time"])
		var best_clip := "-" if best.is_empty() else String(best["clip"])
		var pose_cost := 0.0 if best.is_empty() else float(best["pose_cost"])
		var velocity_cost := 0.0 if best.is_empty() else float(best["velocity_cost"])
		var trajectory_cost := 0.0 if best.is_empty() else float(best["trajectory_cost"])
		var facing_cost := 0.0 if best.is_empty() else float(best["facing_cost"])
		var gate := "SWITCH" if switched else _last_gate_reason
		_readout.text = "MOTION MATCHING — MULTI CLIP\nINPUT %s\nCURRENT %s [%s]  #%d t %.2f cost %.2f\nBEST %s  #%d t %.2f cost %.2f\npose %.2f vel %.2f traj %.2f face %.2f\n%s  cross-clip %d  blend %.2f" % [
			query_label,
			_database.get_sample_clip_name(_current_sample),
			_database.get_sample_role(_current_sample),
			_current_sample,
			_database.get_sample_time(_current_sample),
			current_total,
			best_clip,
			best_sample,
			best_time,
			best_total,
			pose_cost,
			velocity_cost,
			trajectory_cost,
			facing_cost,
			gate,
			_cross_clip_switches,
			1.0 if not _blend_active else clampf(_blend_elapsed / CROSSFADE_DURATION, 0.0, 1.0),
		]

	var desired_points: Array[Vector3] = [Vector3(0.0, TRAJECTORY_Y, 0.0)]
	for horizon in FUTURE_HORIZONS:
		desired_points.append(Vector3(
			desired_local_velocity.x * float(horizon),
			TRAJECTORY_Y,
			desired_local_velocity.y * float(horizon)
		))
	_draw_ribbon_arrow(_desired_mesh_instance, _desired_material, desired_points, DESIRED_COLOR)

	var selected_y := TRAJECTORY_Y + SELECTED_Y_OFFSET
	var selected_points: Array[Vector3] = [Vector3(0.0, selected_y, 0.0)]
	if not best.is_empty():
		var row := _database.get_feature_row(int(best["sample_index"]))
		if row.size() >= 27:
			for feature_index in [21, 23, 25]:
				selected_points.append(Vector3(row[feature_index], selected_y, row[feature_index + 1]))
	_draw_ribbon_arrow(_selected_mesh_instance, _selected_material, selected_points, SELECTED_COLOR)


func _draw_ribbon_arrow(
		instance: MeshInstance3D,
		material: StandardMaterial3D,
		points: Array[Vector3],
		color: Color
	) -> void:
	if instance == null or material == null:
		return
	var mesh := instance.mesh as ImmediateMesh
	if mesh == null:
		return
	mesh.clear_surfaces()
	if points.size() < 2:
		return

	var has_drawable_segment := false
	for segment_index in range(points.size() - 1):
		var test_direction := points[segment_index + 1] - points[segment_index]
		test_direction.y = 0.0
		if test_direction.length_squared() > 0.000001:
			has_drawable_segment = true
			break
	if not has_drawable_segment:
		return

	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for segment_index in range(points.size() - 1):
		var p0 := points[segment_index]
		var p1 := points[segment_index + 1]
		var direction := p1 - p0
		direction.y = 0.0
		if direction.length_squared() <= 0.000001:
			continue
		direction = direction.normalized()
		var side := Vector3(-direction.z, 0.0, direction.x) * RIBBON_HALF_WIDTH
		_add_colored_triangle(mesh, p0 - side, p0 + side, p1 + side, color)
		_add_colored_triangle(mesh, p0 - side, p1 + side, p1 - side, color)

	var tip := points[points.size() - 1]
	var before_tip := points[points.size() - 2]
	var arrow_direction := tip - before_tip
	arrow_direction.y = 0.0
	if arrow_direction.length_squared() > 0.000001:
		arrow_direction = arrow_direction.normalized()
		var arrow_side := Vector3(-arrow_direction.z, 0.0, arrow_direction.x)
		var base_center := tip - arrow_direction * ARROW_LENGTH
		_add_colored_triangle(mesh, tip, base_center + arrow_side * ARROW_HALF_WIDTH, base_center - arrow_side * ARROW_HALF_WIDTH, color)
	mesh.surface_end()


func _add_colored_triangle(
		mesh: ImmediateMesh,
		a: Vector3,
		b: Vector3,
		c: Vector3,
		color: Color
	) -> void:
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(a)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(b)
	mesh.surface_set_color(color)
	mesh.surface_add_vertex(c)
