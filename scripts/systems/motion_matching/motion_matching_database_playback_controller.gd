class_name MotionMatchingDatabasePlaybackController
extends RefCounted

## Experimental Motion Matching player: the simulation moves the body, the
## animated root follows by root motion with adjustment, clamping and crossfade.

const MATCH_INTERVAL := 0.10
const SWITCH_COOLDOWN := 0.20
const CROSSFADE_DURATION := 0.20
const SWITCH_MIN_ABSOLUTE := 0.25
const SWITCH_MIN_RATIO := 0.10
## Same-range poses closer than this to the playing pose are not candidates.
const POSE_JUMP_THRESHOLD_SECONDS := 0.5
## Poses played within this window are not reselected (UE PoseReselectHistory).
const POSE_RESELECT_HISTORY_SECONDS := 1.0
## Remaining samples at which the playing range forces a search.
const FORCE_SEARCH_SAMPLES := 4
const ADJUST_POSITION_HALFLIFE := 0.1
const ADJUST_ROTATION_HALFLIFE := 0.2
const ADJUST_MAX_RATIO := 0.5
## UE5 Steering (Animation Warping): a clip moving faster than this may also turn
## toward the facing at up to STEERING_MAX_RATE, even when it does not rotate.
const STEERING_MIN_SPEED := 0.3
## About the data's 95th-percentile yaw rate.
const STEERING_MAX_RATE := 2.0
const CLAMP_MAX_DISTANCE := 0.15
const CLAMP_MAX_ANGLE := PI * 0.5
const LN2 := 0.69314718056
## Halflife of the pose difference left by an inertialized handover, seconds.
const ENTRY_HALFLIFE := 0.1
## Bones left to the production head-look layer (author decision, #202): the
## database keeps the source gaze, presentation does not apply it.
const GAZE_LAYER_BONES := ["neck_01", "Head"]
const LEG_BONES := [["thigh_l", "calf_l", "foot_l"], ["thigh_r", "calf_r", "foot_r"]]
## Holden's ik_max_length_buffer: a locked leg never snaps to full extension.
const LEG_LENGTH_BUFFER := 0.015
## IK shortfall past which a locked ankle counts as out of reach, metres.
const REACH_TOLERANCE := 0.01

## Presentation only: the query reads the pose before the lock is applied.
var foot_lock_enabled := true
## Lab: the spring simulation moves the body. Game: the body moves itself and
## `follow` mirrors it.
var drive_body := true
## Lab: neck and head at UAL rest. Game: left to the AnimationTree and head look.
var write_gaze_rest := true
## Share of the matched pose over the pose already on the skeleton (the tree's).
var weight := 1.0
## Henry is settling to stand: no new searches, both feet held where they are, so
## handing the pose to a standing animation slides nothing.
var settle := false
## Pose targets left to the pose already on the skeleton, by share (a held
## prop's arm stays the AnimationTree's).
var tree_layer: Dictionary = {}

## Inertialized entry: per pose target the remaining rotation difference (axis
## times angle) and its velocity; the pelvis difference likewise.
var _entry_pending := false
var _entry_active := false
var _entry_rotation: Array[Vector3] = []
var _entry_rotation_velocity: Array[Vector3] = []
var _entry_pelvis := Vector3.ZERO
var _entry_pelvis_velocity := Vector3.ZERO

var _database: MotionDatabase
var _skeleton: Skeleton3D
var _body: CharacterBody3D
var _visual: Node3D
var _simulation := MotionCharacterSimulation.new()
var _anim_position := Vector3.ZERO
var _anim_yaw := 0.0
var _ground_offset := 1.0
var _clamp_events := 0
var _pelvis_bone := -1
var _pose_targets := PackedInt32Array()
## Rest translations: the database poses every bone but the pelvis at rest length.
var _rest_positions := PackedVector3Array()
var _gaze_rest: Dictionary = {}
var _leg_targets: Array[PackedInt32Array] = []
var _foot_lock := MotionFootLock.new()
var _builder := MotionRuntimeQueryBuilder.new()
var _matcher := MotionMatcher.new()
var _debug: MotionMatchingDebugView

var _current := {"sample": 0, "phase": 0.0}
var _previous := {"sample": -1, "phase": 0.0}
var _blend_elapsed := CROSSFADE_DURATION
var _cooldown := 0.0
var _match_timer := 0.0
var _previous_state: Dictionary = {}
var _root_velocity_world := Vector3.ZERO
var _angular_velocity := 0.0
var _prediction: Dictionary = {}
var _last_query := PackedFloat32Array()
var _last_best: Dictionary = {}
var _last_current_cost: Dictionary = {}
var _last_decision := "START"
var _last_switched := false

var _evaluations := 0
var _switches: Array[Dictionary] = []
var _blocked: Dictionary = {}
var _forced_switches := 0
var _foot_slide_sum := 0.0
var _foot_slide_frames := 0
var _steady_slide_sum := 0.0
var _steady_slide_frames := 0
var _since_switch := 1.0
var _clock := 0.0
var _history: Array[Dictionary] = []
var _entry_sample := 0
var _previous_contact_feet: Dictionary = {}
var _previous_animated_feet: Dictionary = {}
var _visual_rest := Transform3D.IDENTITY
var _restart_pending := false
var _animated_slide_sum := 0.0
var _animated_steady_sum := 0.0
var _lock_offset_sum := 0.0
var _lock_offset_frames := 0
var _lock_offset_max := 0.0
var _out_of_reach_frames := 0
var _reach_shortfall_max := 0.0


func setup(database: MotionDatabase, skeleton: Skeleton3D, body: CharacterBody3D, visual: Node3D, debug_view: MotionMatchingDebugView, initial_sample: int) -> bool:
	if database == null or not database.is_consistent() or skeleton == null or body == null or visual == null:
		return false
	_database = database
	_skeleton = skeleton
	_body = body
	_visual = visual
	_visual_rest = visual.transform
	_debug = debug_view
	var model := skeleton.global_transform.orthonormalized()
	var forward := model.basis * Vector3.BACK
	_anim_yaw = atan2(forward.x, forward.z)
	_anim_position = Vector3(model.origin.x, 0.0, model.origin.z)
	_ground_offset = body.global_position.y - model.origin.y
	_simulation.reset(body.global_position, _anim_yaw)
	_pose_targets.resize(database.pose_bone_names.size())
	_entry_rotation.resize(database.pose_bone_names.size())
	_entry_rotation_velocity.resize(database.pose_bone_names.size())
	_rest_positions.clear()
	for pose_index in range(database.pose_bone_names.size()):
		var bone := skeleton.find_bone(database.pose_bone_names[pose_index])
		if bone < 0:
			push_error("MotionMatchingPlayback: Henry lacks bone %s." % database.pose_bone_names[pose_index])
			return false
		_pose_targets[pose_index] = bone
		_rest_positions.append(skeleton.get_bone_rest(bone).origin)
	_pelvis_bone = skeleton.find_bone("pelvis")
	for bone_name in GAZE_LAYER_BONES:
		var pose_index := database.pose_bone_names.find(bone_name)
		var bone := skeleton.find_bone(bone_name)
		if pose_index >= 0 and bone >= 0:
			_gaze_rest[pose_index] = skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	for names in LEG_BONES:
		var leg := PackedInt32Array()
		for bone_name in names:
			leg.append(skeleton.find_bone(bone_name))
		if leg.has(-1):
			push_error("MotionMatchingPlayback: Henry lacks a leg bone of %s." % str(names))
			return false
		_leg_targets.append(leg)
	_current = {"sample": clampi(initial_sample, 0, database.get_sample_count() - 1), "phase": 0.0}
	_entry_sample = _current["sample"]
	_apply_pose()
	_previous_state = _builder.capture(skeleton)
	return not _previous_state.is_empty()


## Lab step: the spring simulation takes the analog intent (world space) and
## moves the body.
func step(dt: float, desired_velocity_world: Vector3, desired_forward_world: Vector3, debug_label: String = "") -> Dictionary:
	_step_simulation(dt, desired_velocity_world, desired_forward_world)
	return _play(dt, _simulation.predict(desired_velocity_world, desired_forward_world), desired_velocity_world, debug_label)


## Game step: the body already moved this tick; `prediction` is its own future
## ({positions, forwards} at MotionCharacterSimulation.FUTURE_HORIZONS).
func follow(dt: float, prediction: Dictionary, desired_velocity_world: Vector3, debug_label: String = "") -> Dictionary:
	var forward := -_body.global_transform.basis.z
	_simulation.mirror(_body.global_position, _body.velocity, atan2(forward.x, forward.z), dt)
	return _play(dt, prediction, desired_velocity_world, debug_label)


## Re-anchors on the visual's current transform and pose (e.g. after the tree
## owned Henry); `keep_feet` carries held foot locks over, a teleport drops them.
func restart(keep_feet: bool = false) -> void:
	var forward := _visual.global_transform.basis * Vector3.BACK
	_anim_yaw = atan2(forward.x, forward.z)
	_anim_position = Vector3(_visual.global_position.x, 0.0, _visual.global_position.z)
	_previous = {"sample": -1, "phase": 0.0}
	if not keep_feet:
		_foot_lock.reset()
	_previous_contact_feet.clear()
	_previous_animated_feet.clear()
	_restart_pending = true


## Leaves `bones` to the pose already on the skeleton by `share` (0 clears).
func set_tree_layer(bones: PackedStringArray, share: float) -> void:
	tree_layer.clear()
	if share <= 0.0:
		return
	for pose_index in range(_pose_targets.size()):
		if bones.has(_skeleton.get_bone_name(_pose_targets[pose_index])):
			tree_layer[pose_index] = clampf(share, 0.0, 1.0)


## Takes over from the pose on the skeleton at once: the next matched pose plays
## in full and the difference decays (Bollo's inertialization, Gears of War).
func begin_inertial_entry() -> void:
	_entry_pending = true


## Tracks the live pose while another system animates, so the first matched
## step has real velocities.
func observe() -> void:
	_previous_state = _builder.capture(_skeleton)


## While another system animates Henry standing still, planted feet stay on their
## lock points; `hold` false releases them through the lock's inertialization.
func hold_feet(dt: float, hold: bool) -> void:
	if not foot_lock_enabled:
		return
	var state := _builder.capture(_skeleton)
	for side in range(2):
		var animated: Vector3 = state[LEG_BONES[side][2]]
		var target := _foot_lock.update(side, animated, hold and _foot_lock.is_locked(side), dt, MotionFootLock.HOLD_LEASH_RADIUS)
		_reach_foot(side, state, target - animated)


func _play(dt: float, prediction: Dictionary, desired_velocity_world: Vector3, debug_label: String) -> Dictionary:
	_cooldown = maxf(0.0, _cooldown - dt)
	_blend_elapsed += dt
	_since_switch += dt
	_clock += dt
	_integrate_root_motion(dt)
	_advance(_current, dt)
	if _previous["sample"] >= 0:
		_advance(_previous, dt)
	_decay_entry(dt)
	_apply_pose()

	# Matching data is the animation; the foot lock below only changes what is drawn.
	var state := _builder.capture(_skeleton)
	_root_velocity_world = (state["model"].origin - _previous_state["model"].origin) / dt
	_angular_velocity = MotionRuntimeQueryBuilder.angular_velocity(_previous_state["model"], state["model"], dt)
	_prediction = prediction
	if foot_lock_enabled:
		_lock_feet(state, dt)
	_measure_foot_slide(state, dt)

	_match_timer += dt
	_last_switched = false
	var forced := _restart_pending or _database.get_samples_to_range_end(_current["sample"]) <= FORCE_SEARCH_SAMPLES
	if (_match_timer >= MATCH_INTERVAL and not settle) or forced:
		_match_timer = 0.0
		_last_query = _builder.build(_previous_state, state, dt, _prediction)
		if _last_query.size() == _database.feature_count:
			_evaluate(forced, desired_velocity_world, debug_label)
	_restart_pending = false
	_previous_state = state
	if _debug != null:
		_debug.update_view(self)
	return get_snapshot()


func get_database() -> MotionDatabase:
	return _database


func get_body() -> Node3D:
	return _body


func get_simulation() -> MotionCharacterSimulation:
	return _simulation


func get_skeleton() -> Skeleton3D:
	return _skeleton


func get_prediction() -> Dictionary:
	return _prediction


func get_foot_lock() -> MotionFootLock:
	return _foot_lock if foot_lock_enabled else null


func get_blend_alpha() -> float:
	return 1.0 if _previous["sample"] < 0 else clampf(_blend_elapsed / CROSSFADE_DURATION, 0.0, 1.0)


func get_snapshot() -> Dictionary:
	var sample: int = _current["sample"]
	return {
		"current_sample": sample,
		"current_clip": _database.get_sample_clip_name(sample),
		"current_time": _database.get_sample_time(sample) + float(_current["phase"]) / _database.sample_rate_hz,
		"current_role_metadata": _database.get_sample_role(sample),
		"root_position": _vec3(_body.global_position),
		"anim_to_simulation_m": Vector2(_anim_position.x - _simulation.position.x, _anim_position.z - _simulation.position.z).length(),
		"anim_to_simulation_yaw": wrapf(_anim_yaw - _simulation.yaw, -PI, PI),
		"root_velocity_world": _vec3(_root_velocity_world),
		"root_speed": Vector2(_root_velocity_world.x, _root_velocity_world.z).length(),
		"angular_velocity": _angular_velocity,
		"blend_alpha": get_blend_alpha(),
		"cooldown": _cooldown,
		"decision": _last_decision,
		"switched": _last_switched,
		"best": _last_best.duplicate(),
		"current_cost": _last_current_cost.duplicate(),
		"candidate_count": int(_last_best.get("candidate_count", 0)),
		"contacts": _database.get_sample_contacts(sample),
		"frame_root_motion": [_database.features[sample * _database.feature_count], _database.features[sample * _database.feature_count + 1], _database.features[sample * _database.feature_count + 2]],
		"clamp_events": _clamp_events,
	}


func get_report() -> Dictionary:
	var cross_clip := 0
	for event in _switches:
		if event["from_clip"] != event["to_clip"]:
			cross_clip += 1
	return {
		"mode": "live_root_space_motion_matching",
		"search_scope": "all_database_samples_except_range_tails_no_role_gate",
		"query_state_source": "live_Henry_skeleton_and_body_motion",
		"future_intent_source": "critically_damped_spring_from_live_velocity",
		"labels_affect_matching": false,
		"movement_authority": "CharacterBody via spring simulation; animated root follows by root motion + adjustment + clamping",
		"adjust_position_halflife_s": ADJUST_POSITION_HALFLIFE,
		"adjust_rotation_halflife_s": ADJUST_ROTATION_HALFLIFE,
		"adjust_max_ratio": ADJUST_MAX_RATIO,
		"steering_max_rate_rad_s": STEERING_MAX_RATE,
		"clamp_max_distance_m": CLAMP_MAX_DISTANCE,
		"clamp_events": _clamp_events,
		"match_interval_s": MATCH_INTERVAL,
		"switch_cooldown_s": SWITCH_COOLDOWN,
		"crossfade_s": CROSSFADE_DURATION,
		"switch_min_absolute": SWITCH_MIN_ABSOLUTE,
		"switch_min_ratio": SWITCH_MIN_RATIO,
		"pose_jump_threshold_s": POSE_JUMP_THRESHOLD_SECONDS,
		"pose_reselect_history_s": POSE_RESELECT_HISTORY_SECONDS,
		"gaze_layer_bones": GAZE_LAYER_BONES,
		"end_margin_samples": _matcher.end_margin_samples,
		"feature_groups": _matcher.get_group_report(),
		"evaluations": _evaluations,
		"switch_count": _switches.size(),
		"cross_clip_switch_count": cross_clip,
		"forced_switch_count": _forced_switches,
		"blocked": _blocked.duplicate(),
		"foot_lock_enabled": foot_lock_enabled,
		"foot_lock_leash_radius_m": MotionFootLock.LEASH_RADIUS,
		"foot_lock_blend_halflife_s": MotionFootLock.BLEND_HALFLIFE,
		"mean_contact_foot_slide_m_s": _ratio(_foot_slide_sum, _foot_slide_frames),
		"steady_contact_foot_slide_m_s": _ratio(_steady_slide_sum, _steady_slide_frames),
		"steady_contact_frame_fraction": _ratio(float(_steady_slide_frames), _foot_slide_frames),
		"animated_mean_contact_foot_slide_m_s": _ratio(_animated_slide_sum, _foot_slide_frames),
		"animated_steady_contact_foot_slide_m_s": _ratio(_animated_steady_sum, _steady_slide_frames),
		"foot_lock_mean_offset_m": _ratio(_lock_offset_sum, _lock_offset_frames),
		"foot_lock_max_offset_m": _lock_offset_max,
		"foot_lock_leash_frames": _foot_lock.leash_frames,
		"foot_lock_out_of_reach_frames": _out_of_reach_frames,
		"foot_lock_max_reach_shortfall_m": _reach_shortfall_max,
		"switch_events": _switches.duplicate(true),
	}


func _evaluate(forced: bool, desired_velocity_world: Vector3, debug_label: String) -> void:
	_evaluations += 1
	var playing: int = _current["sample"]
	var jump := int(round(POSE_JUMP_THRESHOLD_SECONDS * _database.sample_rate_hz))
	var excluded: Array[Vector2i] = [_range_around(playing, jump)]
	for entry in _history:
		if _clock - float(entry["time"]) <= POSE_RESELECT_HISTORY_SECONDS:
			excluded.append(entry["interval"])
	_last_current_cost = _matcher.score_sample(_database, playing, _last_query)
	_last_best = _matcher.find_best(_database, _last_query, excluded)
	if _last_best.is_empty() or _last_current_cost.is_empty():
		_last_decision = "NO MATCH"
		return
	var current_total := float(_last_current_cost["total_cost"])
	var best_total := float(_last_best["total_cost"])
	var best_sample := int(_last_best["sample_index"])
	var required := maxf(SWITCH_MIN_ABSOLUTE, current_total * SWITCH_MIN_RATIO)
	var decision := "SWITCH"
	if not forced:
		if current_total - best_total <= required:
			decision = "CONTINUE (best not better by %.2f)" % required
		elif _cooldown > 0.0:
			decision = "BLOCKED cooldown"
	var restarting := _restart_pending
	_last_decision = decision if not forced else ("FORCED (restart)" if restarting else "FORCED (range end)")
	if decision != "SWITCH":
		var key := decision.get_slice(" (", 0)
		_blocked[key] = int(_blocked.get(key, 0)) + 1
		return
	if forced and not restarting:
		_forced_switches += 1
	_switches.append({
		"debug_label": debug_label,
		"from_clip": _database.get_sample_clip_name(_current["sample"]),
		"from_time": _database.get_sample_time(_current["sample"]),
		"to_clip": _last_best["clip"],
		"to_time": _last_best["time"],
		"to_sample": best_sample,
		"to_role_metadata": _last_best["role"],
		"current_cost": current_total,
		"best_cost": best_total,
		"forced": forced,
		"restart": restarting,
		"desired_velocity": _vec3(desired_velocity_world),
		"candidates": _last_best.get("candidate_count", 0),
	})
	var played := Vector2i(_range_around(_entry_sample, jump).x, _range_around(_current["sample"], jump).y)
	_history.append({"interval": played, "time": _clock})
	_history = _history.filter(func(entry: Dictionary) -> bool: return _clock - float(entry["time"]) <= POSE_RESELECT_HISTORY_SECONDS)
	# On a restart the tree-to-matching handover is the blend, not a crossfade.
	_previous = {"sample": -1, "phase": 0.0} if restarting else _current.duplicate()
	_current = {"sample": best_sample, "phase": 0.0}
	_entry_sample = best_sample
	_blend_elapsed = 0.0
	_since_switch = 0.0
	_cooldown = SWITCH_COOLDOWN
	_last_switched = true


## Samples of the same range within `radius` samples of `sample`.
func _range_around(sample: int, radius: int) -> Vector2i:
	var first := sample
	var last := sample
	var clip := _database.get_sample_clip_index(sample)
	for _step in range(radius):
		if first > 0 and _database.get_sample_clip_index(first - 1) == clip:
			first -= 1
		last = _database.get_next_sample_in_clip(last)
	return Vector2i(first, last)


func _advance(slot: Dictionary, dt: float) -> void:
	var phase := float(slot["phase"]) + dt * _database.sample_rate_hz
	var sample: int = slot["sample"]
	while phase >= 1.0:
		var next := _database.get_next_sample_in_clip(sample)
		if next == sample:
			phase = 0.0
			break
		sample = next
		phase -= 1.0
	slot["sample"] = sample
	slot["phase"] = phase


func _step_simulation(dt: float, desired_velocity_world: Vector3, desired_forward_world: Vector3) -> void:
	if not drive_body:
		return
	var start := _simulation.position
	var velocity := _simulation.update(dt, desired_velocity_world, desired_forward_world)
	_body.velocity = Vector3(velocity.x, 0.0, velocity.z)
	# Explicit displacement: the lab steps at capture rate, not the physics tick.
	_body.move_and_collide(_simulation.position - start)
	_simulation.sync_position(_body.global_position)
	# Body forward is -Z; Henry's model forward (+Z) sits behind a PI yaw.
	_body.rotation = Vector3(0.0, _simulation.yaw + PI, 0.0)


func _integrate_root_motion(dt: float) -> void:
	var motion := _slot_root_motion(_current)
	var alpha := get_blend_alpha()
	if alpha < 1.0:
		motion = _slot_root_motion(_previous).lerp(motion, _smooth(alpha))
	var world_velocity := Basis(Vector3.UP, _anim_yaw) * Vector3(motion.x, 0.0, motion.y)
	_anim_position += world_velocity * dt
	_anim_yaw += motion.z * dt
	# Velocity-limited adjustment toward the simulation, then hard clamping.
	var offset := _simulation.position - _anim_position
	var adjustment := offset * (1.0 - exp(-LN2 * dt / ADJUST_POSITION_HALFLIFE))
	var max_step := ADJUST_MAX_RATIO * world_velocity.length() * dt
	_anim_position += adjustment.limit_length(max_step)
	var yaw_offset := wrapf(_simulation.yaw - _anim_yaw, -PI, PI)
	var yaw_adjustment := yaw_offset * (1.0 - exp(-LN2 * dt / ADJUST_ROTATION_HALFLIFE))
	var max_yaw_step := ADJUST_MAX_RATIO * absf(motion.z) * dt
	if Vector2(motion.x, motion.y).length() > STEERING_MIN_SPEED:
		max_yaw_step = maxf(max_yaw_step, STEERING_MAX_RATE * dt)
	_anim_yaw += clampf(yaw_adjustment, -max_yaw_step, max_yaw_step)
	var remaining := _anim_position - _simulation.position
	if remaining.length() > CLAMP_MAX_DISTANCE:
		_anim_position = _simulation.position + remaining.normalized() * CLAMP_MAX_DISTANCE
		_clamp_events += 1
	var remaining_yaw := wrapf(_anim_yaw - _simulation.yaw, -PI, PI)
	if absf(remaining_yaw) > CLAMP_MAX_ANGLE:
		_anim_yaw = _simulation.yaw + signf(remaining_yaw) * CLAMP_MAX_ANGLE
		_clamp_events += 1
	var ground := Vector3(_anim_position.x, _body.global_position.y - _ground_offset, _anim_position.z)
	var matched := Transform3D(Basis(Vector3.UP, _anim_yaw), ground)
	if weight < 1.0:
		var rest := (_body.global_transform * _visual_rest).orthonormalized()
		matched = rest.interpolate_with(matched, weight)
	_visual.global_transform = matched


func _slot_root_motion(slot: Dictionary) -> Vector3:
	var sample: int = slot["sample"]
	var base := sample * _database.feature_count
	var next := _database.get_next_sample_in_clip(sample) * _database.feature_count
	var t := float(slot["phase"])
	return Vector3(
		lerpf(_database.features[base], _database.features[next], t),
		lerpf(_database.features[base + 1], _database.features[next + 1], t),
		lerpf(_database.features[base + 2], _database.features[next + 2], t)
	)


func _apply_pose() -> void:
	var alpha := _smooth(get_blend_alpha())
	var blending := alpha < 1.0
	var layered := weight < 1.0
	for pose_index in range(_pose_targets.size()):
		var bone := _pose_targets[pose_index]
		if _gaze_rest.has(pose_index):
			if write_gaze_rest:
				_skeleton.set_bone_pose_rotation(bone, _gaze_rest[pose_index])
			continue
		var rotation := _slot_rotation(_current, pose_index)
		if blending:
			rotation = _slot_rotation(_previous, pose_index).slerp(rotation, alpha)
		if _entry_pending:
			_entry_rotation[pose_index] = _rotation_vector(_skeleton.get_bone_pose_rotation(bone) * rotation.inverse())
			_entry_rotation_velocity[pose_index] = Vector3.ZERO
		if _entry_active or _entry_pending:
			rotation = _vector_rotation(_entry_rotation[pose_index]) * rotation
		var keep: float = 1.0 - weight * (1.0 - float(tree_layer.get(pose_index, 0.0)))
		if keep > 0.0:
			rotation = rotation.slerp(_skeleton.get_bone_pose_rotation(bone), keep)
		_skeleton.set_bone_pose_rotation(bone, rotation)
		# Over an AnimationTree the clip's bone translations must not leak in.
		if not drive_body and bone != _pelvis_bone:
			_skeleton.set_bone_pose_position(bone, _skeleton.get_bone_pose_position(bone).lerp(_rest_positions[pose_index], weight))
	var pelvis := _slot_pelvis(_current)
	if blending:
		pelvis = _slot_pelvis(_previous).lerp(pelvis, alpha)
	if _entry_pending:
		_entry_pelvis = _skeleton.get_bone_pose_position(_pelvis_bone) - pelvis
		_entry_pelvis_velocity = Vector3.ZERO
		_entry_pending = false
		_entry_active = true
	if _entry_active:
		pelvis += _entry_pelvis
	if layered:
		pelvis = _skeleton.get_bone_pose_position(_pelvis_bone).lerp(pelvis, weight)
	_skeleton.set_bone_pose_position(_pelvis_bone, pelvis)
	if not blending:
		_previous = {"sample": -1, "phase": 0.0}


## Decays what is left of an inertialized entry; ends it once nothing shows.
func _decay_entry(dt: float) -> void:
	if not _entry_active:
		return
	var largest := 0.0
	for pose_index in range(_entry_rotation.size()):
		var decayed := _spring_decay(_entry_rotation[pose_index], _entry_rotation_velocity[pose_index], dt)
		_entry_rotation[pose_index] = decayed[0]
		_entry_rotation_velocity[pose_index] = decayed[1]
		largest = maxf(largest, decayed[0].length())
	var pelvis := _spring_decay(_entry_pelvis, _entry_pelvis_velocity, dt)
	_entry_pelvis = pelvis[0]
	_entry_pelvis_velocity = pelvis[1]
	_entry_active = largest > 0.001 or _entry_pelvis.length() > 0.0005


## Critically damped decay of an offset and its velocity (Holden's
## decay_spring_damper_exact), at ENTRY_HALFLIFE.
static func _spring_decay(offset: Vector3, velocity: Vector3, dt: float) -> Array[Vector3]:
	var y := 2.0 * LN2 / ENTRY_HALFLIFE
	var j := velocity + offset * y
	var e := exp(-y * dt)
	return [e * (offset + j * dt), e * (velocity - j * y * dt)]


## Shortest rotation as axis times angle, and back.
static func _rotation_vector(rotation: Quaternion) -> Vector3:
	var q := -rotation if rotation.w < 0.0 else rotation
	var angle := q.get_angle()
	return q.get_axis() * angle if angle > 0.000001 else Vector3.ZERO


static func _vector_rotation(vector: Vector3) -> Quaternion:
	var angle := vector.length()
	return Quaternion(vector / angle, angle) if angle > 0.000001 else Quaternion.IDENTITY


func _slot_rotation(slot: Dictionary, pose_index: int) -> Quaternion:
	var sample: int = slot["sample"]
	var a := _database.get_pose_rotation(sample, pose_index)
	var b := _database.get_pose_rotation(_database.get_next_sample_in_clip(sample), pose_index)
	return a.slerp(b, float(slot["phase"]))


func _slot_pelvis(slot: Dictionary) -> Vector3:
	var sample: int = slot["sample"]
	return _database.get_pelvis_position(sample).lerp(_database.get_pelvis_position(_database.get_next_sample_in_clip(sample)), float(slot["phase"]))


## Holds planted ankles on their lock points with a two-bone leg solve.
func _lock_feet(state: Dictionary, dt: float) -> void:
	var contacts := 3 if settle else _database.get_sample_contacts(_current["sample"])
	for side in range(2):
		var animated: Vector3 = state[LEG_BONES[side][2]]
		var leash := MotionFootLock.HOLD_LEASH_RADIUS if settle else MotionFootLock.LEASH_RADIUS
		var target := _foot_lock.update(side, animated, contacts & (1 << side) != 0, dt, leash)
		# A planted foot holds through a handover; only a swinging one fades with it.
		var offset := (target - animated) * (1.0 if _foot_lock.is_locked(side) else weight)
		if not _reach_foot(side, state, offset):
			continue
		if _foot_lock.is_locked(side):
			_lock_offset_sum += offset.length()
			_lock_offset_frames += 1
			_lock_offset_max = maxf(_lock_offset_max, offset.length())


## Moves the ankle by `offset` (world) with the leg solve; a lock the leg cannot
## reach is pulled along. False when there was nothing to move.
func _reach_foot(side: int, state: Dictionary, offset: Vector3) -> bool:
	if offset.length_squared() < 0.00000001:
		return false
	var leg := _leg_targets[side]
	var to_rig: Basis = (state["model"] as Transform3D).basis.inverse()
	var moved := LegTwoBoneIK.reach(_skeleton, leg[0], leg[1], leg[2], to_rig * offset, LEG_LENGTH_BUFFER)
	var missed := (state["model"] as Transform3D).basis * moved - offset
	_reach_shortfall_max = maxf(_reach_shortfall_max, missed.length())
	if missed.length() > REACH_TOLERANCE:
		_out_of_reach_frames += 1
		_foot_lock.pull(side, missed)
	return true


## Planted-foot slide as drawn (after the lock) and as animated (before it).
func _measure_foot_slide(state: Dictionary, dt: float) -> void:
	var contacts := _database.get_sample_contacts(_current["sample"])
	var model: Transform3D = state["model"]
	for side in range(2):
		var key: String = LEG_BONES[side][2]
		var animated: Vector3 = state[key]
		var drawn := model * _skeleton.get_bone_global_pose(_leg_targets[side][2]).origin
		var planted := contacts & (1 << side) != 0
		if planted and _previous_contact_feet.has(key):
			var slide := _flat_distance(drawn, _previous_contact_feet[key]) / dt
			var animated_slide := _flat_distance(animated, _previous_animated_feet[key]) / dt
			_foot_slide_sum += slide
			_animated_slide_sum += animated_slide
			_foot_slide_frames += 1
			if _since_switch > CROSSFADE_DURATION + 0.1:
				_steady_slide_sum += slide
				_animated_steady_sum += animated_slide
				_steady_slide_frames += 1
		if planted:
			_previous_contact_feet[key] = drawn
			_previous_animated_feet[key] = animated
		else:
			_previous_contact_feet.erase(key)
			_previous_animated_feet.erase(key)


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _ratio(total: float, count: int) -> float:
	return 0.0 if count == 0 else total / float(count)


func _smooth(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _vec3(value: Vector3) -> Array:
	return [value.x, value.y, value.z]
