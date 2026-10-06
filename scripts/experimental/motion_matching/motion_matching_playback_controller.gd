class_name MotionMatchingPlaybackController
extends RefCounted

## Experimental issue #202 playback layer.
## Converts brute-force BEST samples into visible Henry playback while keeping
## the existing CMU -> RetargetModifier3D -> UAL path untouched.
##
## CharacterBody3D remains authoritative for world movement. This controller
## only seeks pose time, advances the matched source naturally, gates switches,
## blends rotations, and draws debug trajectories.

const FUTURE_HORIZONS := [0.2, 0.5, 0.8]
const MATCH_INTERVAL := 0.10
const SWITCH_COOLDOWN := 0.28
const CROSSFADE_DURATION := 0.16
const SWITCH_MIN_ABSOLUTE := 1.0
const SWITCH_MIN_RATIO := 0.12
const DESIRED_COLOR := Color(0.18, 1.0, 0.30, 1.0)
const SELECTED_COLOR := Color(0.15, 0.55, 1.0, 1.0)
const TRAJECTORY_Y := -0.965
const RIBBON_HALF_WIDTH := 0.028
const ARROW_LENGTH := 0.22
const ARROW_HALF_WIDTH := 0.10

var _lab: CMUUALRetargetLab
var _database: MotionDatabase
var _tree: SceneTree
var _henry_animation: HenryUALAnimation
var _skeleton: Skeleton3D
var _source: CMUBVHSource
var _readout: Label3D

var _builder := MotionRuntimeQueryBuilder.new()
var _matcher := MotionMatcher.new()

var _playback_time := 0.0
var _previous_pose: Dictionary = {}
var _current_sample := -1
var _cooldown_remaining := 0.0
var _match_accumulator := 0.0
var _last_query_label := ""
var _last_best: Dictionary = {}
var _last_current_cost: Dictionary = {}
var _last_switched := false

var _blend_active := false
var _blend_elapsed := 0.0
var _blend_from_rotations: Array[Quaternion] = []

var _desired_mesh_instance: MeshInstance3D
var _selected_mesh_instance: MeshInstance3D
var _desired_material: StandardMaterial3D
var _selected_material: StandardMaterial3D

var _match_evaluations := 0
var _switch_events: Array[Dictionary] = []


func setup(lab: CMUUALRetargetLab, database: MotionDatabase, initial_time: float) -> bool:
	if lab == null or database == null or not database.is_consistent():
		return false
	_lab = lab
	_database = database
	_tree = lab.get_tree()
	_henry_animation = lab.get_node_or_null(^"Henry/HenryUALVisual") as HenryUALAnimation
	_source = lab.get_node_or_null(^"SourceData/CMU_41_02") as CMUBVHSource
	_readout = lab.get_node_or_null(^"Debug/Readout") as Label3D
	if _tree == null or _henry_animation == null or _henry_animation.skeleton == null or _source == null:
		return false
	_skeleton = _henry_animation.skeleton
	_prepare_debug_meshes()

	_playback_time = _wrap_time(initial_time)
	_lab.seek_capture_time(_playback_time)
	await _tree.process_frame
	_previous_pose = _builder.capture_pose(_skeleton)
	_current_sample = _sample_index_at_time(_playback_time)
	_match_accumulator = MATCH_INTERVAL
	_update_debug(Vector2.ZERO, "START", {}, {}, false)
	return not _previous_pose.is_empty()


func step(delta: float, desired_local_velocity: Vector2, query_label: String) -> Dictionary:
	if _lab == null or _database == null or _skeleton == null or _source == null:
		return {}

	var dt := maxf(delta, 0.000001)
	_cooldown_remaining = maxf(0.0, _cooldown_remaining - dt)
	_playback_time = _wrap_time(_playback_time + dt)
	_lab.seek_capture_time(_playback_time)
	await _tree.process_frame

	if _blend_active:
		_blend_elapsed += dt
		_apply_crossfade_to_current_source_pose()

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
			await _evaluate_and_maybe_switch(query, desired_local_velocity, query_label)
			if _last_switched:
				current_pose = _builder.capture_pose(_skeleton)

	_previous_pose = current_pose.duplicate(true)
	_update_debug(desired_local_velocity, query_label, _last_current_cost, _last_best, _last_switched)
	return get_snapshot()


func get_snapshot() -> Dictionary:
	return {
		"playback_time": _playback_time,
		"current_sample": _current_sample,
		"cooldown_remaining": _cooldown_remaining,
		"blend_active": _blend_active,
		"blend_alpha": 1.0 if not _blend_active else clampf(_blend_elapsed / CROSSFADE_DURATION, 0.0, 1.0),
		"last_query_label": _last_query_label,
		"last_switched": _last_switched,
		"last_best": _last_best.duplicate(true),
		"current_cost": _last_current_cost.duplicate(true),
	}


func get_report() -> Dictionary:
	return {
		"mode": "best_exact_time_seek_natural_continuation",
		"search_interval_seconds": MATCH_INTERVAL,
		"switch_cooldown_seconds": SWITCH_COOLDOWN,
		"crossfade_seconds": CROSSFADE_DURATION,
		"switch_min_absolute_improvement": SWITCH_MIN_ABSOLUTE,
		"switch_min_ratio": SWITCH_MIN_RATIO,
		"match_evaluations": _match_evaluations,
		"switch_count": _switch_events.size(),
		"switch_events": _switch_events.duplicate(true),
		"last_snapshot": get_snapshot(),
		"debug": {
			"desired_trajectory": "green",
			"selected_best_trajectory": "blue",
			"readout": "CURRENT / BEST / costs",
		},
	}


func _build_live_query(
		previous_pose: Dictionary,
		current_pose: Dictionary,
		delta: float,
		desired_local_velocity: Vector2
	) -> PackedFloat32Array:
	var previous_time := _wrap_time(_playback_time - delta)
	var previous_root := _source.get_raw_root_position(previous_time)
	var current_root := _source.get_raw_root_position(_playback_time)
	var root_velocity := (current_root - previous_root) / maxf(delta, 0.000001)

	var previous_facing_3d := _source.get_raw_root_facing(previous_time)
	var current_facing_3d := _source.get_raw_root_facing(_playback_time)
	var previous_facing := _safe_facing(Vector2(previous_facing_3d.x, previous_facing_3d.z))
	var current_facing := _safe_facing(Vector2(current_facing_3d.x, current_facing_3d.z))
	var root_angular_velocity := previous_facing.angle_to(current_facing) / maxf(delta, 0.000001)

	return _builder.build_query(
		previous_pose,
		current_pose,
		delta,
		root_velocity,
		root_angular_velocity,
		current_facing,
		desired_local_velocity,
		Vector2(0.0, 1.0)
	)


func _evaluate_and_maybe_switch(
		query: PackedFloat32Array,
		desired_local_velocity: Vector2,
		query_label: String
	) -> void:
	_match_evaluations += 1
	_current_sample = _sample_index_at_time(_playback_time)
	_last_current_cost = _matcher.score_sample(_database, _current_sample, query)
	_last_best = _matcher.find_best(_database, query)
	if _last_best.is_empty() or _last_current_cost.is_empty():
		return

	var current_total := float(_last_current_cost["total"])
	var best_total := float(_last_best["total_cost"])
	var improvement := current_total - best_total
	var required_improvement := maxf(SWITCH_MIN_ABSOLUTE, current_total * SWITCH_MIN_RATIO)
	var best_sample := int(_last_best["sample_index"])
	var separated_sample: bool = best_sample < _current_sample - 2 or best_sample > _current_sample + 2
	var should_switch: bool = (
		_cooldown_remaining <= 0.0
		and separated_sample
		and improvement > required_improvement
	)

	if should_switch:
		var from_time := _playback_time
		var from_sample := _current_sample
		_begin_crossfade()
		_playback_time = _wrap_time(float(_last_best["time"]))
		_current_sample = best_sample
		_lab.seek_capture_time(_playback_time)
		await _tree.process_frame
		_apply_crossfade_to_current_source_pose()
		_cooldown_remaining = SWITCH_COOLDOWN
		_last_switched = true
		var event := {
			"query": query_label,
			"from_sample": from_sample,
			"from_time": from_time,
			"to_sample": best_sample,
			"to_time": _playback_time,
			"current_cost": current_total,
			"best_cost": best_total,
			"improvement": improvement,
			"required_improvement": required_improvement,
			"desired_velocity": [desired_local_velocity.x, desired_local_velocity.y],
		}
		_switch_events.append(event)
		print("[MM_PLAYBACK_SWITCH] %-13s %d@%.3f -> %d@%.3f improvement=%.3f required=%.3f" % [
			query_label,
			from_sample,
			from_time,
			best_sample,
			_playback_time,
			improvement,
			required_improvement,
		])


func _begin_crossfade() -> void:
	_blend_from_rotations.clear()
	_blend_from_rotations.resize(_skeleton.get_bone_count())
	for bone_index in range(_skeleton.get_bone_count()):
		_blend_from_rotations[bone_index] = _skeleton.get_bone_pose_rotation(bone_index)
	_blend_elapsed = 0.0
	_blend_active = true


func _apply_crossfade_to_current_source_pose() -> void:
	if not _blend_active or _blend_from_rotations.size() != _skeleton.get_bone_count():
		return
	var alpha := clampf(_blend_elapsed / CROSSFADE_DURATION, 0.0, 1.0)
	for bone_index in range(_skeleton.get_bone_count()):
		var source_rotation := _skeleton.get_bone_pose_rotation(bone_index)
		_skeleton.set_bone_pose_rotation(
			bone_index,
			_blend_from_rotations[bone_index].slerp(source_rotation, alpha)
		)
	if alpha >= 0.999:
		_blend_active = false
		_blend_from_rotations.clear()


func _sample_index_at_time(time_seconds: float) -> int:
	if _database == null or _database.get_sample_count() <= 0:
		return -1
	var sample_index := int(round(time_seconds * _database.sample_rate_hz))
	return clampi(sample_index, 0, _database.get_sample_count() - 1)


func _wrap_time(time_seconds: float) -> float:
	if _source == null or _source.clip_length <= 0.0001:
		return maxf(0.0, time_seconds)
	return fposmod(time_seconds, _source.clip_length)


func _safe_facing(value: Vector2) -> Vector2:
	if value.length_squared() <= 0.000001:
		return Vector2(0.0, -1.0)
	return value.normalized()


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
		var pose_cost := 0.0 if best.is_empty() else float(best["pose_cost"])
		var velocity_cost := 0.0 if best.is_empty() else float(best["velocity_cost"])
		var trajectory_cost := 0.0 if best.is_empty() else float(best["trajectory_cost"])
		var facing_cost := 0.0 if best.is_empty() else float(best["facing_cost"])
		var gate := "SWITCH" if switched else "HOLD"
		_readout.text = "MOTION MATCHING — LIVE\nINPUT  %s\nCURRENT  sample %d  t %.3f  cost %.2f\nBEST     sample %d  t %.3f  cost %.2f\npose %.2f  vel %.2f  traj %.2f  facing %.2f\n%s   cooldown %.2f   blend %.2f" % [
			query_label,
			_current_sample,
			_playback_time,
			current_total,
			best_sample,
			best_time,
			best_total,
			pose_cost,
			velocity_cost,
			trajectory_cost,
			facing_cost,
			gate,
			_cooldown_remaining,
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

	var selected_points: Array[Vector3] = [Vector3(0.0, TRAJECTORY_Y + 0.018, 0.0)]
	if not best.is_empty():
		var row := _database.get_feature_row(int(best["sample_index"]))
		if row.size() >= 27:
			for feature_index in [21, 23, 25]:
				selected_points.append(Vector3(
					row[feature_index],
					TRAJECTORY_Y + 0.018,
					row[feature_index + 1]
				))
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
		_add_colored_triangle(
			mesh,
			tip,
			base_center + arrow_side * ARROW_HALF_WIDTH,
			base_center - arrow_side * ARROW_HALF_WIDTH,
			color
		)
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
