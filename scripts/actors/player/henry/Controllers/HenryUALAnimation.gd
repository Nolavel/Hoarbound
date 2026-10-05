class_name HenryUALAnimation
extends Node3D

## Henry locomotion animation component.
##
## Same ownership rule as ADT's PlayerAnimationComponent:
## - the AnimationTree is assembled entirely in GDScript (no .tres tree),
## - the component only READS Player state,
## - it has no _process/_physics_process of its own,
## - Player.gd explicitly calls update_animation_blend() after move_and_slide(),
##   so animation sees the velocity that actually survived collision/slope handling.
##
## UAL is strictly in-place. CharacterBody3D remains authoritative for motion.

enum WorkPose { NONE, ENTERING, HOLDING, EXITING, RETURNING }

const MOVEMENT_EPSILON: float = 0.05
## Slowest a slowed walk plays before it would read as standing still.
const MIN_WALK_PACE: float = 0.35
const WORK_POSE_HOLD_SECONDS: float = 2.6

const IDLE_ALIASES: Array[StringName] = [&"Idle_Loop", &"Idle"]
const WALK_ALIASES: Array[StringName] = [&"Walk_Loop", &"Walk"]
const JOG_ALIASES: Array[StringName] = [&"Jog_Fwd_Loop", &"Jog_Fwd"]
const SPRINT_ALIASES: Array[StringName] = [&"Sprint_Loop", &"Sprint"]
const CROUCH_IDLE_ALIASES: Array[StringName] = [&"Crouch_Idle_Loop", &"Crouch_Idle"]
const CROUCH_FWD_ALIASES: Array[StringName] = [&"Crouch_Fwd_Loop", &"Crouch_Fwd"]
const JUMP_START_ALIASES: Array[StringName] = [&"Jump_Start"]
const JUMP_LOOP_ALIASES: Array[StringName] = [&"Jump_Loop"]
const JUMP_LAND_ALIASES: Array[StringName] = [&"Jump_Land"]
const SIT_ENTER_ALIASES: Array[StringName] = [&"Sitting_Enter"]
const SIT_LOOP_ALIASES: Array[StringName] = [&"Sitting_Idle", &"Sitting_Idle_Loop"]
const SIT_EXIT_ALIASES: Array[StringName] = [&"Sitting_Exit"]
const TORCH_ALIASES: Array[StringName] = [&"Idle_Torch", &"Idle_Torch_Loop"]
const CARRY_WALK_ALIASES: Array[StringName] = [&"UAL2/Walk_Carry", &"Walk_Carry_Loop"]  # Godot drops _Loop on import
## Bones the carry pose leaves to the idle clip; the rest hold the load.
const LOWER_BODY_BONES: Array[StringName] = [&"root", &"pelvis", &"spine_01", &"thigh_l", &"calf_l",
	&"foot_l", &"ball_l", &"thigh_r", &"calf_r", &"foot_r", &"ball_r", &"ball_leaf_l", &"ball_leaf_r"]
## Full-body actions during which Henry stands still.
const LOCKING_ACTIONS: Array[StringName] = [
	&"interact", &"pickup", &"pickup_right_shelf", &"pickup_right_low", &"fix", &"chest_open",
]
## Walking speed of the authored carry cycle, m/s.
const CARRY_WALK_SPEED: float = 1.5
## Kenny's feet sit this far below his origin; he is lifted by it when set down.
const KENNY_SEAT_HEIGHT: float = 0.19
const INTERACTIVE_SCENE: String = "res://scenes/environment/interactive/InteractiveArea.tscn"
const PACK_INSPECT_SCRIPT: String = "res://scripts/actors/player/henry/pack/pack_inspect_prompt.gd"

const ACTION_ALIASES: Dictionary = {
	&"interact": [&"Interact"],
	&"pickup": [&"PickUp_Table", &"Pickup_Table"],
	## Complete UAL actions used by the embodied-interaction proof. These are not
	## pose samples: AnimationTree owns the full enter/contact/return motion.
	&"pickup_right_shelf": [&"UAL2/Farm_Watering", &"Farm_Watering"],
	&"pickup_right_low": [&"UAL2/Farm_Harvest", &"Farm_Harvest"],
	&"fix": [&"Fixing_Kneeling"],
	&"consume": [&"Consume", &"UAL2/Consume"],
	&"chest_open": [&"Chest_Open", &"UAL2/Chest_Open"],
	&"hit_chest": [&"Hit_Chest"],
	&"hit_head": [&"Hit_Head"],
	&"sit_enter": [&"Sitting_Enter"],
	&"sit_exit": [&"Sitting_Exit"],
}

@export_group("Locomotion Blend")
## Position of the authored walk cycle in normalized 0..1 real speed.
## Henry walks at 1.5 m/s and sprints at 4.5 m/s, so 0.33 is physical.
@export_range(0.1, 0.75, 0.01) var walk_blend_position: float = 0.33
## Jog sits between walk and full sprint. This is a feel point rather than a
## separate gameplay speed tier: MovementController still owns actual speed.
@export_range(0.5, 0.95, 0.01) var jog_blend_position: float = 0.67

@export_group("Visual")
@export var portrait_render_layers: int = 16
## Flat colour for the placeholder mannequin until Henry has a final model.
@export var body_color: Color = Color(0.55, 0.56, 0.58)
## Second UAL clip set, added to the player under its own library name.
@export var secondary_library_scene: PackedScene
@export var secondary_library_name: StringName = &"UAL2"

@export_group("Head look")
## Bone the procedural look turns; ADT's head look, on the UAL rig.
@export var head_bone: StringName = &"Head"
## Side-to-side head turn each way from straight ahead, degrees.
@export var head_look_primary_limit_deg: float = 55.0
## The UAL head's rest pose is yawed off the body; this re-centres the limit.
@export var head_rest_yaw_offset_deg: float = 13.0
@export var head_look_secondary_limit_deg: float = 45.0
@export var head_look_duration: float = 0.25
## Below this speed Henry counts as standing and the head follows the camera, m/s.
@export var head_look_idle_speed: float = 0.15
## How fast the look marker chases its point, and the influence fade per second.
@export var head_look_smooth: float = 8.0
@export var head_look_fade_speed: float = 4.0
## Distance the look point is held at, metres.
@export var head_look_distance: float = 5.0
## Head forward axis in bone space; flip it if the head looks sideways or back.
@export var head_forward_axis: SkeletonModifier3D.BoneAxis = SkeletonModifier3D.BONE_AXIS_PLUS_Z

@export_group("Backpack")
@export var backpack_bone: StringName = &"spine_03"
@export var backpack_size: Vector3 = Vector3(0.34, 0.44, 0.2)
## Offset from the bone in model space; the mannequin faces +Z, so back is -Z.
@export var backpack_offset: Vector3 = Vector3(0.0, 0.0, -0.2)
@export var backpack_color: Color = Color(0.36, 0.33, 0.28)
## Outfit meshes from tools/blender/build_henry_outfit.py per equipment mesh name.
## Skin_<name> is the body under that garment, hidden while it is worn.
const GARMENT_PARTS: Dictionary = {
	&"Hat": [&"Outfit_Beanie", &"Outfit_BeanieCuff"],
	&"Coat": [&"Outfit_Jacket", &"Outfit_Skirt", &"Outfit_Hood", &"Outfit_Trim"],
	&"Trousers": [&"Outfit_Pants"],
	&"Boots": [&"Outfit_Boots", &"Outfit_Sole"],
}
## How much fully soaked clothing darkens.
@export_range(0.0, 1.0, 0.05) var wet_darkening: float = 0.45
## Kenny's faded plush, lighter than the pack so the silhouette separates.
@export var kenny_color: Color = Color(0.55, 0.45, 0.34)

@export_group("Held in hand")
## Bone of the shared held-item socket; flares and later lights use it.
## UAL's Idle_Torch raises the left hand, so held lights ride there.
@export var hand_bone: StringName = &"hand_l"
## Prop offset from the hand bone, in the bone's space.
## Pushed past the fingers and tipped out of the fist, so the tube and its
## burning tip read clear of Henry's hand.
@export var hand_prop_offset: Vector3 = Vector3(0.0, 0.12, 0.06)
@export var hand_prop_rotation_deg: Vector3 = Vector3(-55.0, 0.0, 0.0)
## Right hand is reserved for a selected board while the left holds the hammer.
@export var offhand_bone: StringName = &"hand_r"
@export var offhand_prop_offset: Vector3 = Vector3(0.02, 0.16, 0.04)
@export var offhand_prop_rotation_deg: Vector3 = Vector3(0.0, 0.0, 90.0)
## How fast the right arm eases into and out of the held pose.
@export_range(1.0, 20.0, 0.5) var hold_pose_rate: float = 8.0

@export_group("Carried load")
## Bone the armful rides on; the carry cycle keeps both hands around it.
@export var carry_bone: StringName = &"spine_03"
## Load centre from the bone in model space: +Z is in front of Henry.
@export var carry_offset: Vector3 = Vector3(0.0, -0.14, 0.3)

@onready var player: CharacterBody3D = get_parent() as CharacterBody3D
@onready var model: Node = $Model

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var animation_tree: AnimationTree
var _state_playback: AnimationNodeStateMachinePlayback
var _action_node: AnimationNodeAnimation

## Meshes a garment names in GarmentData.mesh_node_name.
var _garment_meshes: Dictionary = {}
var _pack: PackRig
## Where the pack and Kenny hang while set down: [parent, local transform].
var _pack_home: Array = []
var _kenny_home: Array = []
## Garment name to the skin mesh it covers.
var _skin_parts: Dictionary = {}
## Garment name to its material, darkened by wetness.
var _garment_materials: Dictionary = {}
var _wetness: float = 0.0
var _equipment: EquipmentComponent
var _head_lookat: LookAtModifier3D
var _head_target: Node3D
var _head_influence: float = 0.0

var _blend_position: float = 0.0
var _resolved_idle: StringName = &""
var _resolved_walk: StringName = &""
var _resolved_jog: StringName = &""
var _resolved_sprint: StringName = &""
var _resolved_crouch_idle: StringName = &""
var _resolved_crouch_fwd: StringName = &""
var _resolved_jump_start: StringName = &""
var _resolved_jump_loop: StringName = &""
var _resolved_jump_land: StringName = &""
var _resolved_carry_walk: StringName = &""
var _resolved_torch: StringName = &""
var _hand_socket: BoneAttachment3D
var _held_prop: Node3D
var _offhand_socket: BoneAttachment3D
var _offhand_prop: Node3D
var _hold_pose: float = 0.0
var _current_action: StringName = &""
var _work_pose: WorkPose = WorkPose.NONE
var _work_pose_time: float = 0.0
var _work_pose_length: float = 0.0
var _work_pose_blend: float = 0.0
var _work_clip: AnimationNodeAnimation
var _carried: ItemResource = null
var _carried_count: int = 0
var _sitting: bool = false
var _resolved_sit_enter: StringName = &""
var _resolved_sit_loop: StringName = &""
var _resolved_sit_exit: StringName = &""
## Props shown in Henry's arms while carried, by ItemResource.attached_mesh_node_name.
var _carry_props: Dictionary = {}


func _ready() -> void:
	if player == null:
		push_error("HenryUALAnimation must be a direct child of Player.")
		return

	animation_player = _find_animation_player(model)
	skeleton = _find_skeleton(model)
	_set_mesh_layers_recursive(model, portrait_render_layers)

	if animation_player == null:
		push_error("HenryUALAnimation: rigged Henry has no AnimationPlayer.")
		return

	if skeleton == null:
		push_warning("HenryUALAnimation: rigged Henry has no Skeleton3D.")
	else:
		print("Henry UAL skeleton ready: %d bones" % skeleton.get_bone_count())

	_paint_body()
	_attach_backpack()
	_attach_garments()
	_attach_carry_props()
	_bind_equipment()
	_setup_head_look()
	_setup_wade()
	_make_animation_library_local()
	_add_secondary_library()
	_setup_animation_tree()


## Called explicitly from Player.gd AFTER move_and_slide().
## No input intent is used here: only real horizontal velocity, the same
## principle ADT uses so animation cannot visually outrun physics.
func update_animation_blend(_delta: float) -> void:
	if animation_tree == null or player == null:
		return
	_update_work_pose(_delta)
	var hold_target: float = 1.0 if is_instance_valid(_held_prop) and _work_pose == WorkPose.NONE else 0.0
	_hold_pose = move_toward(_hold_pose, hold_target, hold_pose_rate * _delta)
	animation_tree.set("parameters/hold_pose/blend_amount", _hold_pose)

	_blend_position = 0.0
	if player.has_method("get_locomotion_speed_ratio"):
		_blend_position = float(player.call("get_locomotion_speed_ratio"))
	else:
		var planar_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
		_blend_position = clampf(planar_speed / 4.5, 0.0, 1.0)

	if Vector2(player.velocity.x, player.velocity.z).length() < MOVEMENT_EPSILON:
		_blend_position = 0.0

	## Slower than a walk (deep snow, a heavy load): a slowed walk, never half idle,
	## so the feet keep pace with the ground and the idle stance does not lean in.
	var pace: float = 1.0
	if _blend_position > 0.0 and _blend_position < walk_blend_position:
		pace = maxf(_blend_position / walk_blend_position, MIN_WALK_PACE)
		_blend_position = walk_blend_position
	animation_tree.set("parameters/base/Grounded/loco/blend_position", _blend_position)
	animation_tree.set("parameters/base/Grounded/pace/scale", pace)
	var crouch_blend: float = 0.0
	if player.has_method("get_crouch_speed_ratio"):
		crouch_blend = float(player.call("get_crouch_speed_ratio"))
	animation_tree.set("parameters/base/Crouch/blend_position", crouch_blend)
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	animation_tree.set("parameters/base/Carry/arms_pace/scale", speed / CARRY_WALK_SPEED)
	animation_tree.set("parameters/base/Carry/walk_pace/scale", speed / CARRY_WALK_SPEED)
	animation_tree.set("parameters/base/Carry/move/blend_amount", clampf(speed / 0.3, 0.0, 1.0))


func update_animation_state(jump_started: bool, landed: bool) -> void:
	if _state_playback == null or player == null:
		return
	var current: StringName = _state_playback.get_current_node()
	if _has_sit_state():
		if _sitting:
			_state_playback.travel(&"SitLoop")
			return
		if current == &"SitEnter" or current == &"SitLoop":
			_state_playback.travel(&"SitExit")
			return
		if current == &"SitExit":
			return
	if landed:
		_state_playback.travel(&"Land")
		return
	if current == &"Land":
		return
	if jump_started:
		_state_playback.travel(&"JumpStart")
		return
	if current == &"JumpStart":
		return
	if not player.is_on_floor():
		_state_playback.travel(&"AirLoop")
		return
	var crouching: bool = player.has_method("is_crouching") and bool(player.call("is_crouching"))
	if crouching:
		_state_playback.travel(&"Crouch")
	else:
		_state_playback.travel(&"Carry" if _carried != null and _has_carry_state() else &"Grounded")


## Sits down (enter, then the idle loop) or stands up (exit). RestComponent decides.
func set_sitting(sitting: bool) -> void:
	_sitting = sitting


func is_sitting() -> bool:
	return _sitting


func _has_sit_state() -> bool:
	return _resolved_sit_loop != &""


## Shows exactly as many carried units as the inventory owns; null frees hands.
func set_carried_item(item: ItemResource, count: int = 1) -> void:
	_carried = item
	_carried_count = clampi(count, 0, item.hand_carry_limit) if item != null else 0
	var shown: StringName = item.attached_mesh_node_name if item != null else &""
	for prop_name: StringName in _carry_props:
		var bundle := _carry_props[prop_name] as Node3D
		var active: bool = prop_name == shown and _carried_count > 0
		bundle.visible = active
		for index: int in range(bundle.get_child_count()):
			var unit := bundle.get_child(index) as Node3D
			if unit != null:
				unit.visible = active and index < _carried_count


## The shared held-item socket on the right hand, made on first use.
func get_hand_socket() -> BoneAttachment3D:
	if is_instance_valid(_hand_socket) or skeleton == null:
		return _hand_socket
	_hand_socket = BoneAttachment3D.new()
	_hand_socket.name = "HandSocket"
	_hand_socket.bone_name = hand_bone
	skeleton.add_child(_hand_socket)
	return _hand_socket


## Puts a prop in Henry's socket hand and raises the arm into the held pose
## (Idle_Torch over whatever the legs are doing).
func hold_in_hand(prop: Node3D) -> void:
	var socket: BoneAttachment3D = get_hand_socket()
	if socket == null:
		return
	if is_instance_valid(_held_prop) and _held_prop != prop:
		release_hand()
	if prop.get_parent() != null:
		prop.get_parent().remove_child(prop)
	socket.add_child(prop)
	var rot: Vector3 = hand_prop_rotation_deg * (PI / 180.0)
	prop.transform = Transform3D(Basis.from_euler(rot), hand_prop_offset)
	_set_layers_recursive(prop, portrait_render_layers | 1)
	_held_prop = prop


## Takes the prop out of the hand without freeing it; the arm eases down.
func release_hand() -> Node3D:
	var prop: Node3D = _held_prop if is_instance_valid(_held_prop) else null
	_held_prop = null
	if prop != null and prop.get_parent() != null:
		var world_xf: Transform3D = prop.global_transform
		prop.get_parent().remove_child(prop)
		prop.transform = world_xf
	return prop


func get_held_prop() -> Node3D:
	return _held_prop if is_instance_valid(_held_prop) else null


func get_offhand_socket() -> BoneAttachment3D:
	if is_instance_valid(_offhand_socket) or skeleton == null:
		return _offhand_socket
	_offhand_socket = BoneAttachment3D.new()
	_offhand_socket.name = "OffhandSocket"
	_offhand_socket.bone_name = offhand_bone
	skeleton.add_child(_offhand_socket)
	return _offhand_socket


func hold_in_offhand(prop: Node3D) -> void:
	var socket: BoneAttachment3D = get_offhand_socket()
	if socket == null:
		return
	if is_instance_valid(_offhand_prop) and _offhand_prop != prop:
		release_offhand()
	if prop.get_parent() != null:
		prop.get_parent().remove_child(prop)
	socket.add_child(prop)
	var rot: Vector3 = offhand_prop_rotation_deg * (PI / 180.0)
	prop.transform = Transform3D(Basis.from_euler(rot), offhand_prop_offset)
	_set_layers_recursive(prop, portrait_render_layers | 1)
	_offhand_prop = prop


func release_offhand() -> Node3D:
	var prop: Node3D = _offhand_prop if is_instance_valid(_offhand_prop) else null
	_offhand_prop = null
	if prop != null and prop.get_parent() != null:
		var world_xf: Transform3D = prop.global_transform
		prop.get_parent().remove_child(prop)
		prop.transform = world_xf
	return prop


func get_offhand_prop() -> Node3D:
	return _offhand_prop if is_instance_valid(_offhand_prop) else null


func _set_layers_recursive(node: Node, layers: int) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = layers
	for child: Node in node.get_children():
		_set_layers_recursive(child, layers)


func is_carrying() -> bool:
	return _carried != null


## True while a full-body action plays that Henry must stand still for.
func is_action_locking() -> bool:
	if _work_pose != WorkPose.NONE or _work_pose_blend > 0.0:
		return true
	if animation_tree == null or not LOCKING_ACTIONS.has(_current_action):
		return false
	## FIRE has not necessarily been evaluated when F arrives before a physics tick.
	return bool(animation_tree.get("parameters/actions/active")) \
		or int(animation_tree.get("parameters/actions/request")) == AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func _has_carry_state() -> bool:
	return _resolved_carry_walk != &""


func play_action(action: StringName, speed: float = 1.0) -> bool:
	if animation_tree == null or _action_node == null or _work_pose != WorkPose.NONE:
		return false
	var clip_name: StringName = _resolve_action_clip(action)
	if clip_name == &"":
		return false
	var animation: Animation = animation_player.get_animation(clip_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE
	_action_node.animation = clip_name
	_current_action = action
	animation_tree.set("parameters/action_pace/scale", maxf(0.05, speed))
	animation_tree.set("parameters/actions/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	return true


func is_action_active() -> bool:
	if animation_tree == null:
		return false
	return bool(animation_tree.get("parameters/actions/active")) \
		or int(animation_tree.get("parameters/actions/request")) == AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE


func get_action_clip_name(action: StringName) -> StringName:
	return _resolve_action_clip(action)


func get_action_length(action: StringName) -> float:
	var clip_name: StringName = _resolve_action_clip(action)
	if clip_name == &"":
		return 0.0
	var clip: Animation = animation_player.get_animation(clip_name)
	return clip.length if clip != null else 0.0


func abort_action() -> void:
	if animation_tree != null:
		animation_tree.set("parameters/actions/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


## Plays into the kneeling work clip, holds its middle, then resumes its exit.
func begin_work_pose() -> bool:
	var clip_name: StringName = _resolve_action_clip(&"fix")
	if animation_tree == null or _work_clip == null or clip_name == &"" or _work_pose in [WorkPose.ENTERING, WorkPose.HOLDING]:
		return false
	var clip: Animation = animation_player.get_animation(clip_name)
	if clip == null or clip.length <= WORK_POSE_HOLD_SECONDS:
		return false
	abort_action()
	clip.loop_mode = Animation.LOOP_NONE
	_work_clip.animation = clip_name
	_work_pose_length = clip.length
	_work_pose_time = minf(_work_pose_time, WORK_POSE_HOLD_SECONDS) if _work_pose in [WorkPose.EXITING, WorkPose.RETURNING] else 0.0
	_work_pose = WorkPose.ENTERING
	animation_tree.set("parameters/work_seek/seek_request", _work_pose_time)
	return true


func is_work_pose_ready() -> bool:
	return _work_pose == WorkPose.HOLDING


func end_work_pose() -> void:
	if _work_pose == WorkPose.ENTERING:
		_work_pose = WorkPose.RETURNING
	elif _work_pose == WorkPose.HOLDING:
		_work_pose = WorkPose.EXITING


func _update_work_pose(delta: float) -> void:
	if _work_pose == WorkPose.ENTERING:
		_work_pose_time = minf(_work_pose_time + delta, WORK_POSE_HOLD_SECONDS)
		if _work_pose_time >= WORK_POSE_HOLD_SECONDS:
			_work_pose = WorkPose.HOLDING
	elif _work_pose == WorkPose.RETURNING:
		_work_pose_time = maxf(_work_pose_time - delta, 0.0)
		if _work_pose_time <= 0.0:
			_work_pose = WorkPose.NONE
	elif _work_pose == WorkPose.EXITING:
		_work_pose_time = minf(_work_pose_time + delta, _work_pose_length)
		if _work_pose_time >= _work_pose_length:
			_work_pose = WorkPose.NONE
	_work_pose_blend = move_toward(_work_pose_blend, 0.0 if _work_pose == WorkPose.NONE else 1.0, delta * 10.0)
	animation_tree.set("parameters/work_seek/seek_request", _work_pose_time)
	animation_tree.set("parameters/work_pose/blend_amount", _work_pose_blend)


func _resolve_action_clip(action: StringName) -> StringName:
	if not ACTION_ALIASES.has(action):
		return &""
	var aliases: Array[StringName] = []
	for value: Variant in ACTION_ALIASES[action]:
		aliases.append(StringName(value))
	return _resolve_clip(aliases)


## ADT head look: standing, the head eases toward where the camera looks;
## moving, the clips own the head and the look fades out.
func update_head_look(delta: float) -> void:
	if _head_lookat == null or player == null:
		return
	var planar_speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	var want: bool = planar_speed < head_look_idle_speed and player.has_method(&"get_view_direction")
	var eye: Vector3 = _head_bone_position()
	var direction: Vector3 = -player.global_transform.basis.z
	if want:
		direction = player.call(&"get_view_direction")
	direction.y = 0.0
	var target: Vector3 = eye + direction.normalized() * head_look_distance
	if want and _head_influence <= 0.001:
		_head_target.global_position = target
	else:
		_head_target.global_position = _head_target.global_position.lerp(target, clampf(delta * head_look_smooth, 0.0, 1.0))
	_head_influence = move_toward(_head_influence, 1.0 if want else 0.0, delta * head_look_fade_speed)
	_head_lookat.influence = _head_influence
	_head_lookat.active = _head_influence > 0.001


## Deep-snow wading on top of whatever clip plays; SnowShell drives its `wade`.
func _setup_wade() -> void:
	if skeleton == null or skeleton.get_node_or_null(^"Wade") != null:
		return
	var wade := WadeModifier.new()
	wade.name = "Wade"
	skeleton.add_child(wade)
	var feet := SnowFootModifier.new()
	feet.name = "SnowFeet"
	skeleton.add_child(feet)
	## Last, so the palm lands on the door after spine lean and legs are settled.
	var door_hand := DoorHandIK.new()
	door_hand.name = "DoorHand"
	skeleton.add_child(door_hand)


func _setup_head_look() -> void:
	if skeleton == null or skeleton.find_bone(head_bone) < 0:
		push_warning("HenryUALAnimation: no %s bone, head look disabled." % head_bone)
		return
	_head_target = Node3D.new()
	_head_target.name = "HeadLookTarget"
	add_child(_head_target)
	_head_lookat = LookAtModifier3D.new()
	_head_lookat.name = "HeadLook"
	skeleton.add_child(_head_lookat)
	_head_lookat.bone_name = head_bone
	_head_lookat.forward_axis = head_forward_axis
	## ADT: the flag is use_angle_limitation, and it needs explicit limits and duration.
	_head_lookat.use_angle_limitation = true
	_head_lookat.symmetry_limitation = false
	_head_lookat.primary_positive_limit_angle = deg_to_rad(head_look_primary_limit_deg + head_rest_yaw_offset_deg)
	_head_lookat.primary_negative_limit_angle = deg_to_rad(head_look_primary_limit_deg - head_rest_yaw_offset_deg)
	_head_lookat.secondary_limit_angle = deg_to_rad(head_look_secondary_limit_deg)
	_head_lookat.duration = head_look_duration
	_head_lookat.target_node = _head_lookat.get_path_to(_head_target)
	_head_lookat.influence = 0.0
	_head_lookat.active = false


func _head_bone_position() -> Vector3:
	var bone: int = skeleton.find_bone(head_bone)
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin


func get_locomotion_blend_position() -> float:
	return _blend_position


func get_locomotion_label() -> String:
	if _blend_position <= 0.05:
		return "IDLE"
	if _blend_position < (walk_blend_position + jog_blend_position) * 0.5:
		return "WALK"
	if _blend_position < (jog_blend_position + 1.0) * 0.5:
		return "JOG"
	return "SPRINT"


func _make_animation_library_local() -> void:
	var source_library: AnimationLibrary = animation_player.get_animation_library(&"")
	if source_library == null:
		return

	var local_library := source_library.duplicate(true) as AnimationLibrary
	animation_player.remove_animation_library(&"")
	animation_player.add_animation_library(&"", local_library)


func _add_secondary_library() -> void:
	if secondary_library_scene == null or animation_player.has_animation_library(secondary_library_name):
		return
	var source: Node = secondary_library_scene.instantiate()
	var source_player: AnimationPlayer = _find_animation_player(source)
	if source_player != null and source_player.has_animation_library(&""):
		var library := source_player.get_animation_library(&"").duplicate(true) as AnimationLibrary
		animation_player.add_animation_library(secondary_library_name, library)
	source.free()


func _paint_body() -> void:
	_override_materials(model, StylizedEnvironmentMaterial.make_character(body_color, 0.85))


func _override_materials(node: Node, material: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = material
	for child: Node in node.get_children():
		_override_materials(child, material)


## The four-flap pack rig on the upper spine, until the pack has a mesh.
func _attach_backpack() -> void:
	if skeleton == null:
		return
	var bone: int = skeleton.find_bone(backpack_bone)
	if bone < 0:
		push_warning("HenryUALAnimation: no bone %s for the backpack." % backpack_bone)
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "BackpackAttachment"
	attachment.bone_name = backpack_bone
	skeleton.add_child(attachment)
	var pack := PackRig.new()
	pack.size = backpack_size
	pack.color = backpack_color
	pack.render_layers = portrait_render_layers
	var rest: Transform3D = skeleton.get_bone_global_rest(bone)
	pack.transform = rest.affine_inverse() * Transform3D(Basis.IDENTITY, rest.origin + backpack_offset)
	pack.visible = false
	attachment.add_child(pack)
	pack.build()
	_pack = pack
	_garment_meshes[StringName(pack.name)] = pack
	_attach_kenny(pack)


## Takes the pack off and stands it on the floor at `pack_xf`; Kenny is unstrapped
## and set at `kenny_xf`. Both transforms are floor points; pick_pack_up() undoes it.
func set_pack_down(pack_xf: Transform3D, kenny_xf: Transform3D) -> void:
	if _pack == null or not _pack.is_visible_in_tree() or not _pack_home.is_empty():
		return
	var world: Node = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	_pack.set_openness(PackRig.Openness.AJAR, true)
	_pack_home = [_pack.get_parent(), _pack.transform]
	_pack.reparent(world, false)
	_pack.global_transform = pack_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, backpack_size.y * 0.5, 0.0))
	_add_inspect_prompt()
	var kenny := _garment_meshes.get(&"Kenny") as Node3D
	if kenny != null and kenny.visible:
		_kenny_home = [kenny.get_parent(), kenny.transform]
		kenny.reparent(world, false)
		kenny.global_transform = kenny_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, KENNY_SEAT_HEIGHT, 0.0))


func pick_pack_up() -> void:
	if not _pack_home.is_empty():
		var prompt: Node = _pack.get_node_or_null(^"Inspect")
		if prompt != null:
			prompt.free()
		_pack.set_openness(PackRig.Openness.CLOSED, true)
		_pack.reparent(_pack_home[0], false)
		_pack.transform = _pack_home[1]
		_pack_home = []
	var kenny := _garment_meshes.get(&"Kenny") as Node3D
	if kenny != null and not _kenny_home.is_empty():
		kenny.reparent(_kenny_home[0], false)
		kenny.transform = _kenny_home[1]
		_kenny_home = []


## F — Inspect pack, while it stands on the floor.
func _add_inspect_prompt() -> void:
	var area: Node3D = (load(INTERACTIVE_SCENE) as PackedScene).instantiate()
	area.name = "Inspect"
	area.set_script(load(PACK_INSPECT_SCRIPT))
	area.set(&"interactable_scene", null)
	area.set(&"object_on_ground", false)
	area.set(&"icon_height_offset", 0.4)
	area.set(&"info_height_offset", 0.55)
	var col := area.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if col != null:
		var shape := BoxShape3D.new()
		shape.size = backpack_size + Vector3(0.1, 0.1, 0.1)
		col.shape = shape
	_pack.add_child(area)


func is_pack_down() -> bool:
	return not _pack_home.is_empty()


## The pack on Henry's back, or null before the model is set up.
func get_pack_rig() -> PackRig:
	return _pack


## Kenny strapped to the outside of the pack: a teddy silhouette facing back,
## sat on the pack's lower half. Shown only while he rides on his fixture.
func _attach_kenny(pack: PackRig) -> void:
	var material := StylizedEnvironmentMaterial.make_character(kenny_color, 1.0)
	var kenny := Node3D.new()
	kenny.name = "Kenny"
	## Strapped over the bottom flap, so he swings down with it when the pack opens.
	var hinge: Node3D = pack.get_bottom_flap()
	kenny.transform = hinge.transform.affine_inverse() * Transform3D(Basis.IDENTITY, Vector3(0.0, -0.04, -backpack_size.z * 0.5 - 0.07))
	kenny.visible = false
	hinge.add_child(kenny)
	## [centre, radii] in pack space; +Y up, -Z away from Henry's back.
	var parts: Array = [
		[Vector3(0.0, 0.0, 0.0), Vector3(0.1, 0.12, 0.07)],
		[Vector3(0.0, 0.17, -0.01), Vector3(0.075, 0.07, 0.065)],
		[Vector3(-0.06, 0.235, -0.01), Vector3(0.025, 0.025, 0.015)],
		[Vector3(0.06, 0.235, -0.01), Vector3(0.025, 0.025, 0.015)],
		[Vector3(0.0, 0.16, -0.07), Vector3(0.03, 0.022, 0.02)],
		[Vector3(-0.11, 0.02, -0.01), Vector3(0.03, 0.07, 0.03)],
		[Vector3(0.11, 0.02, -0.01), Vector3(0.03, 0.07, 0.03)],
		[Vector3(-0.05, -0.14, -0.03), Vector3(0.035, 0.05, 0.035)],
		[Vector3(0.05, -0.14, -0.03), Vector3(0.035, 0.05, 0.035)],
	]
	for part: Array in parts:
		var sphere := SphereMesh.new()
		sphere.radius = 1.0
		sphere.height = 2.0
		sphere.radial_segments = 12
		sphere.rings = 6
		sphere.material = material
		var blob := MeshInstance3D.new()
		blob.mesh = sphere
		blob.layers = portrait_render_layers
		blob.transform = Transform3D(Basis.from_scale(part[1]), part[0])
		kenny.add_child(blob)
	var strap := BoxMesh.new()
	strap.size = Vector3(backpack_size.x + 0.02, 0.025, 0.2)
	strap.material = StylizedEnvironmentMaterial.make_character(Color(0.15, 0.14, 0.13), 0.9)
	var band := MeshInstance3D.new()
	band.mesh = strap
	band.layers = portrait_render_layers
	band.position = Vector3(0.0, 0.02, 0.07)
	kenny.add_child(band)
	_garment_meshes[&"Kenny"] = kenny


## Groups the skinned outfit meshes per garment under the skeleton. Hidden
## until the equipment shows them; each keeps its own material for wetness.
func _attach_garments() -> void:
	if skeleton == null:
		return
	for garment_name: StringName in GARMENT_PARTS:
		var group := Node3D.new()
		group.name = String(garment_name)
		group.visible = false
		skeleton.add_child(group)
		for part: StringName in GARMENT_PARTS[garment_name]:
			var mesh_inst := model.find_child(String(part), true, false) as MeshInstance3D
			if mesh_inst == null:
				push_warning("HenryUALAnimation: outfit mesh %s is missing." % part)
				continue
			mesh_inst.material_override = null  # drop the body paint
			for surface: int in mesh_inst.mesh.get_surface_count():
				var source := mesh_inst.mesh.surface_get_material(surface) as BaseMaterial3D
				var dry: Color = source.albedo_color if source != null else body_color
				var material := StylizedEnvironmentMaterial.make_character(dry, 1.0)
				material.set_meta(&"dry_color", dry)
				mesh_inst.set_surface_override_material(surface, material)
				_garment_materials["%s:%d" % [part, surface]] = material
			mesh_inst.reparent(group)
			mesh_inst.skeleton = mesh_inst.get_path_to(skeleton)
		_garment_meshes[garment_name] = group
		var skin := model.find_child("Skin_" + String(garment_name), true, false) as Node3D
		if skin != null:
			_skin_parts[garment_name] = skin


## Three visible slots for two-hand resources: logs and salvaged boards.
func _attach_carry_props() -> void:
	if skeleton == null:
		return
	var bone: int = skeleton.find_bone(carry_bone)
	if bone < 0:
		push_warning("HenryUALAnimation: no bone %s for carried loads." % carry_bone)
		return
	var attachment := BoneAttachment3D.new()
	attachment.name = "CarryAttachment"
	attachment.bone_name = carry_bone
	skeleton.add_child(attachment)
	var rest: Transform3D = skeleton.get_bone_global_rest(bone)
	var load_transform := rest.affine_inverse() * Transform3D(Basis.IDENTITY, rest.origin + carry_offset)

	var firewood := Node3D.new()
	firewood.name = "CarryFirewood"
	firewood.transform = load_transform
	firewood.visible = false
	attachment.add_child(firewood)
	var bark := StylizedEnvironmentMaterial.make_character(Color(0.36, 0.26, 0.18), 1.0)
	var logs: Array = [
		[Vector3(-0.06, 0.0, 0.0), 0.055, 0.46, 4.0],
		[Vector3(0.06, 0.0, 0.01), 0.05, 0.42, -6.0],
		[Vector3(0.0, 0.09, 0.0), 0.05, 0.44, 8.0],
	]
	for spec: Array in logs:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = spec[1]
		cylinder.bottom_radius = spec[1]
		cylinder.height = spec[2]
		cylinder.radial_segments = 7
		cylinder.material = bark
		var log_mesh := MeshInstance3D.new()
		log_mesh.mesh = cylinder
		log_mesh.layers = portrait_render_layers
		log_mesh.transform = Transform3D(Basis.from_euler(Vector3(0.0, deg_to_rad(spec[3]), PI * 0.5)), spec[0])
		firewood.add_child(log_mesh)
	_carry_props[&"CarryFirewood"] = firewood

	var boards := Node3D.new()
	boards.name = "CarryBoards"
	boards.transform = load_transform
	boards.visible = false
	attachment.add_child(boards)
	var wood := StylizedEnvironmentMaterial.make_character(Color(0.42, 0.3, 0.19), 0.95)
	var board_specs: Array = [
		[Vector3(0.0, -0.02, 0.0), -4.0],
		[Vector3(0.0, 0.045, 0.015), 5.0],
		[Vector3(0.0, 0.11, -0.01), -2.0],
	]
	for spec: Array in board_specs:
		var box := BoxMesh.new()
		box.size = Vector3(0.52, 0.035, 0.095)
		box.material = wood
		var board := MeshInstance3D.new()
		board.mesh = box
		board.layers = portrait_render_layers
		board.position = spec[0]
		board.rotation.z = deg_to_rad(spec[1])
		boards.add_child(board)
	_carry_props[&"CarryBoards"] = boards


## Soaked clothing reads darker; 0 dry to 1 soaked.
func set_wetness(wetness: float) -> void:
	_wetness = clampf(wetness, 0.0, 1.0)
	for material: ShaderMaterial in _garment_materials.values():
		var dry: Color = material.get_meta(&"dry_color")
		material.set_shader_parameter("albedo_color", dry.darkened(wet_darkening * _wetness))


## Shows a garment's mesh only while that garment is worn.
func _bind_equipment() -> void:
	if player == null:
		return
	_equipment = player.get_node_or_null(^"EquipmentComponent") as EquipmentComponent
	if _equipment == null:
		return
	_equipment.slot_changed.connect(func(_path: StringName, _item: StringName) -> void: refresh_garment_meshes())
	refresh_garment_meshes()


func refresh_garment_meshes() -> void:
	var worn: Dictionary = {}
	if _equipment != null and _equipment.layout != null:
		for slot: EquipmentSlotDefinition in _equipment.layout.body_slots:
			var id: StringName = _equipment.get_equipped(slot.id)
			var item: ItemResource = ItemCatalog.get_item(id) if id != &"" else null
			if item != null and item.garment != null and item.garment.mesh_node_name != &"":
				worn[item.garment.mesh_node_name] = true
			elif item != null and item.attached_mesh_node_name != &"":
				worn[item.attached_mesh_node_name] = true
	for mesh_name: StringName in _garment_meshes:
		(_garment_meshes[mesh_name] as Node3D).visible = worn.has(mesh_name)
	for garment_name: StringName in _skin_parts:
		(_skin_parts[garment_name] as Node3D).visible = not worn.has(garment_name)


## ADT convention: build the complete graph in code. No editor-authored
## AnimationTree resource exists to drift away from clip names or component code.
func _setup_animation_tree() -> void:
	_resolved_idle = _resolve_clip(IDLE_ALIASES)
	_resolved_walk = _resolve_clip(WALK_ALIASES)
	_resolved_jog = _resolve_clip(JOG_ALIASES)
	_resolved_sprint = _resolve_clip(SPRINT_ALIASES)
	_resolved_crouch_idle = _resolve_clip(CROUCH_IDLE_ALIASES)
	_resolved_crouch_fwd = _resolve_clip(CROUCH_FWD_ALIASES)
	_resolved_jump_start = _resolve_clip(JUMP_START_ALIASES)
	_resolved_jump_loop = _resolve_clip(JUMP_LOOP_ALIASES)
	_resolved_jump_land = _resolve_clip(JUMP_LAND_ALIASES)
	_resolved_carry_walk = _resolve_clip(CARRY_WALK_ALIASES)
	_resolved_torch = _resolve_clip(TORCH_ALIASES)
	_resolved_sit_enter = _resolve_clip(SIT_ENTER_ALIASES)
	_resolved_sit_loop = _resolve_clip(SIT_LOOP_ALIASES)
	_resolved_sit_exit = _resolve_clip(SIT_EXIT_ALIASES)
	if _resolved_carry_walk == &"":
		push_warning("HenryUALAnimation: no Walk_Carry_Loop clip; carrying keeps normal locomotion.")

	if _resolved_idle == &"":
		_resolved_idle = _first_available_clip()
	if _resolved_idle == &"":
		push_error("HenryUALAnimation: no usable UAL animations found.")
		return
	if _resolved_walk == &"": _resolved_walk = _resolved_idle
	if _resolved_jog == &"": _resolved_jog = _resolved_walk
	if _resolved_sprint == &"": _resolved_sprint = _resolved_jog
	if _resolved_crouch_idle == &"": _resolved_crouch_idle = _resolved_idle
	if _resolved_crouch_fwd == &"": _resolved_crouch_fwd = _resolved_crouch_idle
	if _resolved_jump_start == &"": _resolved_jump_start = _resolved_idle
	if _resolved_jump_loop == &"": _resolved_jump_loop = _resolved_jump_start
	if _resolved_jump_land == &"": _resolved_jump_land = _resolved_idle

	for clip_name: StringName in [
		_resolved_idle, _resolved_walk, _resolved_jog, _resolved_sprint,
		_resolved_crouch_idle, _resolved_crouch_fwd, _resolved_jump_loop,
	]:
		_force_locomotion_loop(clip_name)
	_force_clip_once(_resolved_jump_start)
	_force_clip_once(_resolved_jump_land)

	var locomotion := AnimationNodeBlendSpace1D.new()
	locomotion.min_space = 0.0
	locomotion.max_space = 1.0
	locomotion.value_label = "real speed"
	locomotion.sync = true
	locomotion.add_blend_point(_clip(_resolved_idle), 0.0, -1, &"idle")
	locomotion.add_blend_point(_clip(_resolved_walk), walk_blend_position, -1, &"walk")
	locomotion.add_blend_point(_clip(_resolved_jog), jog_blend_position, -1, &"jog")
	locomotion.add_blend_point(_clip(_resolved_sprint), 1.0, -1, &"sprint")

	var crouch := AnimationNodeBlendSpace1D.new()
	crouch.min_space = 0.0
	crouch.max_space = 1.0
	crouch.value_label = "crouch speed"
	crouch.sync = true
	crouch.add_blend_point(_clip(_resolved_crouch_idle), 0.0, -1, &"idle")
	crouch.add_blend_point(_clip(_resolved_crouch_fwd), 1.0, -1, &"forward")

	var grounded := AnimationNodeBlendTree.new()
	grounded.add_node(&"loco", locomotion, Vector2(-200.0, 0.0))
	grounded.add_node(&"pace", AnimationNodeTimeScale.new(), Vector2(0.0, 0.0))
	grounded.connect_node(&"pace", 0, &"loco")
	grounded.connect_node(&"output", 0, &"pace")

	var base := AnimationNodeStateMachine.new()
	base.add_node(&"Grounded", grounded, Vector2(0.0, 0.0))
	base.add_node(&"Crouch", crouch, Vector2(0.0, 180.0))
	base.add_node(&"JumpStart", _clip(_resolved_jump_start), Vector2(260.0, -120.0))
	base.add_node(&"AirLoop", _clip(_resolved_jump_loop), Vector2(520.0, -120.0))
	base.add_node(&"Land", _clip(_resolved_jump_land), Vector2(780.0, 0.0))
	_add_state_transition(base, &"Grounded", &"Crouch", 0.12)
	_add_state_transition(base, &"Crouch", &"Grounded", 0.12)
	_add_state_transition(base, &"Grounded", &"JumpStart", 0.06)
	_add_state_transition(base, &"Crouch", &"JumpStart", 0.06)
	_add_state_transition(base, &"Grounded", &"AirLoop", 0.08)
	_add_state_transition(base, &"Crouch", &"AirLoop", 0.08)
	_add_state_transition(base, &"JumpStart", &"AirLoop", 0.08, true)
	_add_state_transition(base, &"JumpStart", &"Land", 0.05)
	_add_state_transition(base, &"AirLoop", &"Land", 0.08)
	_add_state_transition(base, &"Land", &"Grounded", 0.10, true)
	_add_state_transition(base, &"Land", &"Crouch", 0.10)
	if _has_carry_state():
		_force_locomotion_loop(_resolved_carry_walk)
		base.add_node(&"Carry", _build_carry_tree(), Vector2(0.0, -180.0))
		for other: StringName in [&"Grounded", &"Crouch"]:
			_add_state_transition(base, other, &"Carry", 0.15)
			_add_state_transition(base, &"Carry", other, 0.15)
		_add_state_transition(base, &"Carry", &"JumpStart", 0.06)
		_add_state_transition(base, &"Carry", &"AirLoop", 0.08)
		_add_state_transition(base, &"Land", &"Carry", 0.10)

	if _has_sit_state() and _resolved_sit_enter != &"" and _resolved_sit_exit != &"":
		_force_locomotion_loop(_resolved_sit_loop)
		_force_clip_once(_resolved_sit_enter)
		_force_clip_once(_resolved_sit_exit)
		base.add_node(&"SitEnter", _clip(_resolved_sit_enter), Vector2(-260.0, 120.0))
		base.add_node(&"SitLoop", _clip(_resolved_sit_loop), Vector2(-520.0, 120.0))
		base.add_node(&"SitExit", _clip(_resolved_sit_exit), Vector2(-260.0, 240.0))
		_add_state_transition(base, &"Grounded", &"SitEnter", 0.15)
		_add_state_transition(base, &"SitEnter", &"SitLoop", 0.12, true)
		_add_state_transition(base, &"SitLoop", &"SitExit", 0.12)
		_add_state_transition(base, &"SitEnter", &"SitExit", 0.12)
		_add_state_transition(base, &"SitExit", &"Grounded", 0.15, true)
	else:
		_resolved_sit_loop = &""

	var default_action: StringName = _resolve_action_clip(&"interact")
	_action_node = _clip(default_action if default_action != &"" else _resolved_idle)
	var actions := AnimationNodeOneShot.new()
	actions.fadein_time = 0.08
	actions.fadeout_time = 0.12

	var tree_root := AnimationNodeBlendTree.new()
	tree_root.add_node(&"base", base, Vector2(-560.0, 0.0))
	## The socket's arm (and only it) raised into the held pose over any locomotion.
	var side_suffix: String = String(hand_bone).right(2)
	var hold_pose := AnimationNodeBlend2.new()
	hold_pose.filter_enabled = true
	var torch_clip: StringName = _resolved_torch if _resolved_torch != &"" else _resolved_idle
	_force_locomotion_loop(torch_clip)
	var torch_anim: Animation = animation_player.get_animation(torch_clip)
	for track: int in torch_anim.get_track_count():
		var path: NodePath = torch_anim.track_get_path(track)
		var bone := StringName(path.get_concatenated_subnames())
		if String(bone).ends_with(side_suffix) and not LOWER_BODY_BONES.has(bone):
			hold_pose.set_filter_path(path, true)
	tree_root.add_node(&"hold_clip", _clip(torch_clip), Vector2(-560.0, 220.0))
	tree_root.add_node(&"hold_pose", hold_pose, Vector2(-320.0, 0.0))
	tree_root.connect_node(&"hold_pose", 0, &"base")
	tree_root.connect_node(&"hold_pose", 1, &"hold_clip")
	tree_root.add_node(&"action_clip", _action_node, Vector2(-360.0, 220.0))
	tree_root.add_node(&"action_pace", AnimationNodeTimeScale.new(), Vector2(-220.0, 220.0))
	tree_root.add_node(&"actions", actions, Vector2(-80.0, 0.0))
	tree_root.connect_node(&"actions", 0, &"hold_pose")
	tree_root.connect_node(&"action_pace", 0, &"action_clip")
	tree_root.connect_node(&"actions", 1, &"action_pace")
	_work_clip = _clip(_resolved_idle)
	tree_root.add_node(&"work_clip", _work_clip, Vector2(-560.0, 440.0))
	tree_root.add_node(&"work_seek", AnimationNodeTimeSeek.new(), Vector2(-360.0, 440.0))
	tree_root.add_node(&"work_pace", AnimationNodeTimeScale.new(), Vector2(-160.0, 440.0))
	tree_root.add_node(&"work_pose", AnimationNodeBlend2.new(), Vector2(120.0, 0.0))
	tree_root.connect_node(&"work_seek", 0, &"work_clip")
	tree_root.connect_node(&"work_pace", 0, &"work_seek")
	tree_root.connect_node(&"work_pose", 0, &"actions")
	tree_root.connect_node(&"work_pose", 1, &"work_pace")
	tree_root.connect_node(&"output", 0, &"work_pose")

	animation_tree = AnimationTree.new()
	animation_tree.name = "AnimationTree"
	animation_tree.tree_root = tree_root
	add_child(animation_tree)
	animation_tree.anim_player = animation_tree.get_path_to(animation_player)
	animation_tree.active = true
	animation_tree.set("parameters/action_pace/scale", 1.0)
	animation_tree.set("parameters/work_pace/scale", 0.0)
	animation_tree.set("parameters/base/Grounded/loco/blend_position", 0.0)
	animation_tree.set("parameters/base/Crouch/blend_position", 0.0)
	animation_tree.set("parameters/base/Carry/arms/blend_amount", 1.0)
	_state_playback = animation_tree.get("parameters/base/playback") as AnimationNodeStateMachinePlayback
	if _state_playback != null:
		_state_playback.start(&"Grounded")


## Carry locomotion: the carry cycle at real speed while moving; standing, the
## idle legs with the carry cycle's arms frozen around the load.
func _build_carry_tree() -> AnimationNodeBlendTree:
	var tree := AnimationNodeBlendTree.new()
	tree.add_node(&"idle", _clip(_resolved_idle), Vector2(-400.0, 0.0))
	## Frozen arms for standing and the full cycle for walking; a node output
	## feeds only one input, so each branch has its own clip and pace.
	for branch: String in ["arms", "walk"]:
		tree.add_node(StringName(branch + "_clip"), _clip(_resolved_carry_walk), Vector2(-600.0, 200.0))
		tree.add_node(StringName(branch + "_pace"), AnimationNodeTimeScale.new(), Vector2(-400.0, 200.0))
		tree.connect_node(StringName(branch + "_pace"), 0, StringName(branch + "_clip"))
	var arms := AnimationNodeBlend2.new()
	arms.filter_enabled = true
	var clip: Animation = animation_player.get_animation(_resolved_carry_walk)
	for track: int in clip.get_track_count():
		var path: NodePath = clip.track_get_path(track)
		if not LOWER_BODY_BONES.has(StringName(path.get_concatenated_subnames())):
			arms.set_filter_path(path, true)
	tree.add_node(&"arms", arms, Vector2(-200.0, 0.0))
	tree.connect_node(&"arms", 0, &"idle")
	tree.connect_node(&"arms", 1, &"arms_pace")
	tree.add_node(&"move", AnimationNodeBlend2.new(), Vector2(0.0, 0.0))
	tree.connect_node(&"move", 0, &"arms")
	tree.connect_node(&"move", 1, &"walk_pace")
	tree.connect_node(&"output", 0, &"move")
	return tree


func _add_state_transition(state_machine: AnimationNodeStateMachine, from: StringName, to: StringName, xfade: float, auto_advance: bool = false) -> void:
	var transition := AnimationNodeStateMachineTransition.new()
	transition.xfade_time = xfade
	if auto_advance:
		transition.advance_mode = AnimationNodeStateMachineTransition.ADVANCE_MODE_AUTO
		transition.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_AT_END
	state_machine.add_transition(from, to, transition)


func _force_locomotion_loop(animation_name: StringName) -> void:
	if animation_name == &"":
		return
	var animation: Animation = animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_LINEAR


func _force_clip_once(animation_name: StringName) -> void:
	if animation_name == &"":
		return
	var animation: Animation = animation_player.get_animation(animation_name)
	if animation != null:
		animation.loop_mode = Animation.LOOP_NONE


func _clip(animation_name: StringName) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = animation_name
	return node


func _resolve_clip(candidates: Array[StringName]) -> StringName:
	for candidate: StringName in candidates:
		if animation_player.has_animation(candidate):
			return candidate

	var available: PackedStringArray = animation_player.get_animation_list()
	for candidate: StringName in candidates:
		var expected: String = _normalize_clip_name(candidate)
		for actual_text: String in available:
			var actual := StringName(actual_text)
			if _normalize_clip_name(actual) == expected:
				return actual
	return &""


func _normalize_clip_name(animation_name: StringName) -> String:
	var normalized := String(animation_name).to_lower().replace(" ", "_")
	if normalized.ends_with("_armature"):
		normalized = normalized.trim_suffix("_armature")
	if normalized.contains("|"):
		normalized = normalized.get_slice("|", normalized.get_slice_count("|") - 1)
	if normalized.contains("/"):
		normalized = normalized.get_slice("/", normalized.get_slice_count("/") - 1)
	return normalized


func _first_available_clip() -> StringName:
	for animation_name: StringName in animation_player.get_animation_list():
		if animation_name != &"RESET":
			return animation_name
	return &""


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child: Node in node.get_children():
		var found: AnimationPlayer = _find_animation_player(child)
		if found != null:
			return found
	return null


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child: Node in node.get_children():
		var found: Skeleton3D = _find_skeleton(child)
		if found != null:
			return found
	return null


func _set_mesh_layers_recursive(node: Node, layers: int) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).layers = layers
	for child: Node in node.get_children():
		_set_mesh_layers_recursive(child, layers)
