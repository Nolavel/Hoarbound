extends TableInteractionSolverLab

## Interactive adapter for the tabletop lab. InteractComponent owns selection/F;
## this existing action/IK solver owns availability, preparation and contact.
## InventoryComponent still receives the item through ItemPickup.pick_up().
const CONTACT_ERROR_M: float = 0.10
var _interact: InteractComponent
var _profiles: Array[Dictionary] = []
var _busy: bool = false
var _commit_queued: bool = false
var _contact_point: Vector3
var _item_origin: Vector3
var _settle_elapsed: float = 0.0
var last_result: Dictionary = {}

func setup_live(scene: DiegeticInventoryStage) -> void:
	stage = scene
	player = stage.player
	camera = stage.camera
	visual = player.get_node(^"HenryUALVisual") as HenryUALAnimation
	_interact = player.get_node(^"InteractComponent") as InteractComponent
	_build_stock_ik()
	for hand: StringName in [&"LEFT", &"RIGHT"]:
		var action: StringName = &"pickup" if hand == &"LEFT" else &"pickup_right_low"
		var profile := _sample_contact_pose(action, hand)
		if not profile.is_empty():
			_profiles.append(profile)
	_interact.pickup_reach_query = solve_pickup
	_interact.pickup_request = request_pickup
	_left_ik.modification_processed.connect(_verify_contact.bind(&"LEFT"))
	_right_ik.modification_processed.connect(_verify_contact.bind(&"RIGHT"))
	process_priority = 20

## Read the real clip at its authored contact time without mutating live bones.
func _sample_contact_pose(action: StringName, hand: StringName) -> Dictionary:
	var clip_name := visual.get_action_clip_name(action)
	if clip_name == &"":
		return {}
	var clip := visual.animation_player.get_animation(clip_name)
	var sk := visual.skeleton
	var poses: Array[Transform3D] = []
	for bone: int in sk.get_bone_count():
		poses.append(sk.get_bone_rest(bone))
	for track: int in clip.get_track_count():
		var path := clip.track_get_path(track)
		if path.get_subname_count() != 1 or not clip.track_is_enabled(track):
			continue
		var bone := sk.find_bone(path.get_subname(0))
		if bone < 0:
			continue
		var pose := poses[bone]
		match clip.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				pose.origin = clip.position_track_interpolate(track, CONTACT_SECONDS_SOURCE)
			Animation.TYPE_ROTATION_3D:
				pose.basis = Basis(clip.rotation_track_interpolate(track, CONTACT_SECONDS_SOURCE)).scaled(pose.basis.get_scale())
			Animation.TYPE_SCALE_3D:
				pose.basis = Basis(pose.basis.get_rotation_quaternion()).scaled(clip.scale_track_interpolate(track, CONTACT_SECONDS_SOURCE))
		poses[bone] = pose
	var suffix := "l" if hand == &"LEFT" else "r"
	var points: Dictionary = {}
	for role: String in ["upperarm_", "lowerarm_", "hand_"]:
		var bone := sk.find_bone(role + suffix)
		if bone < 0:
			return {}
		var pose := poses[bone]
		var parent := sk.get_bone_parent(bone)
		while parent >= 0:
			pose = poses[parent] * pose
			parent = sk.get_bone_parent(parent)
		points[role] = pose.origin
	return {"action": action, "hand": hand, "shoulder": points["upperarm_"],
		"elbow": points["lowerarm_"], "wrist": points["hand_"]}

func solve_pickup(candidate: ItemPickup) -> Dictionary:
	if _busy or player.is_action_locking() or not is_instance_valid(candidate) or candidate.is_queued_for_deletion() or not candidate.can_interact():
		return {}
	var target: Vector3 = _interact._focus_point(candidate)
	var heading := target - player.global_position
	heading.y = 0.0
	if heading.length_squared() < 0.0001 or _interact.get_facing_direction().dot(heading.normalized()) < 0.5:
		return {}
	var best: Dictionary = {}
	for profile: Dictionary in _profiles:
		var shoulder: Vector3 = visual.skeleton.to_global(profile["shoulder"])
		var suffix := "l" if profile["hand"] == &"LEFT" else "r"
		var live_shoulder := _bone_world("upperarm_" + suffix)
		var live_elbow := _bone_world("lowerarm_" + suffix)
		var live_wrist := _bone_world("hand_" + suffix)
		var arm_length := live_shoulder.distance_to(live_elbow) + live_elbow.distance_to(live_wrist)
		var offset := target - shoulder
		var reach := arm_length * 0.95
		if absf(offset.y) >= reach:
			continue
		var horizontal := Vector3(offset.x, 0.0, offset.z)
		var horizontal_reach := sqrt(reach * reach - offset.y * offset.y)
		var correction := horizontal.normalized() * maxf(0.0, horizontal.length() - horizontal_reach)
		if correction.length() > MAX_SETTLE_M:
			continue
		# A short preparation step uses CharacterBody collision, never a teleport.
		if correction.length() > 0.001 and player.test_move(player.global_transform, correction):
			continue
		var predicted_shoulder := shoulder + correction
		var ray := PhysicsRayQueryParameters3D.create(predicted_shoulder, target)
		ray.exclude = [player.get_rid()]
		if not player.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		var ratio := predicted_shoulder.distance_to(target) / arm_length
		if ratio < 0.30:
			continue
		var same_side := signf(player.to_local(live_shoulder).x) == signf(player.to_local(target).x)
		var score := correction.length() * 4.0 + ratio + (0.0 if same_side else 0.35)
		if best.is_empty() or score < float(best["score"]):
			best = {"hand": profile["hand"], "action": profile["action"], "score": score,
				"stance_position": player.global_position + correction, "settle_distance_m": correction.length(),
				"reach_ratio": ratio, "arm_length_m": arm_length, "contact": target}
	return best

func request_pickup(candidate: ItemPickup) -> void:
	var selected := solve_pickup(candidate)
	if selected.is_empty():
		return
	item = candidate
	solution = selected
	_contact_point = selected["contact"]
	_active_hand = selected["hand"]
	_active_action = selected["action"]
	_item_origin = candidate.global_position
	_settle_to = selected["stance_position"]
	_settle_from_yaw = player.global_rotation.y
	_busy = true
	_commit_queued = false
	_contact_done = false
	_settle_elapsed = 0.0
	last_result = {"item": item.item_id, "accepted": true, "committed": false, "solution": selected.duplicate()}
	_interact._clear_current_target()
	if float(selected["settle_distance_m"]) > 0.025:
		state = State.SETTLE
		player.move_to_position(_settle_to)
	else:
		_start_action()

func _process(delta: float) -> void:
	if not _busy:
		return
	if not is_instance_valid(item) or item.is_queued_for_deletion():
		if not _contact_done:
			_cancel("item_disappeared")
		else:
			_finish()
		return
	if item.global_position.distance_to(_item_origin) > 0.01:
		_cancel("item_moved")
		return
	if state == State.SETTLE:
		_settle_elapsed += delta
		var remaining := Vector2(player.global_position.x - _settle_to.x, player.global_position.z - _settle_to.z).length()
		if remaining <= 0.055:
			player.stop_moving()
			# Restore the requested body heading before starting the in-place action.
			player.global_rotation.y = lerp_angle(player.global_rotation.y, _settle_from_yaw, 1.0 - exp(-12.0 * delta))
			if absf(wrapf(player.global_rotation.y - _settle_from_yaw, -PI, PI)) < 0.03:
				_start_action()
		elif not player.is_walking_to_target() or _settle_elapsed > 2.0:
			_cancel("preparation_interrupted")
		return
	if state != State.ACTION:
		return
	_action_time += delta
	var weight := smoothstep(_contact_time - IK_BLEND_IN_SECONDS, _contact_time, _action_time)
	_set_hand_ik(_active_hand, _contact_point, weight)
	if _action_time > _contact_time + 0.20 and not _contact_done:
		_cancel("contact_missed")

func _verify_contact(hand: StringName) -> void:
	if not _busy or state != State.ACTION or hand != _active_hand or _commit_queued or _action_time < _contact_time:
		return
	var suffix := "l" if hand == &"LEFT" else "r"
	var shoulder := _bone_world("upperarm_" + suffix)
	var elbow := _bone_world("lowerarm_" + suffix)
	var wrist := _bone_world("hand_" + suffix)
	var length := shoulder.distance_to(elbow) + elbow.distance_to(wrist)
	var ratio := shoulder.distance_to(_contact_point) / maxf(length, 0.001)
	var error := wrist.distance_to(_contact_point)
	last_result["contact_error_m"] = error
	last_result["reach_ratio"] = ratio
	if error <= CONTACT_ERROR_M and ratio <= HARD_ARM_FRACTION:
		_commit_queued = true
		_commit.call_deferred()

func _commit() -> void:
	if not _busy or not is_instance_valid(item) or item.is_queued_for_deletion():
		return
	_contact_done = item.pick_up()
	last_result["committed"] = _contact_done
	if _contact_done:
		_interact.complete_authored_pickup(item)
	print("[table-pickup] ", JSON.stringify(last_result))
	_finish()

func _cancel(reason: String) -> void:
	last_result["failure"] = reason
	print("[table-pickup] ", JSON.stringify(last_result))
	visual.abort_action()
	_finish()

func _finish() -> void:
	player.stop_moving()
	_disable_all_ik()
	_busy = false
	_commit_queued = false
	state = State.IDLE
	item = null
