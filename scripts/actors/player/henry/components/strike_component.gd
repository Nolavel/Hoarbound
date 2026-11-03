class_name StrikeComponent
extends Node

## Swings the item in Henry's hand when it is a striking tool (ItemResource.strike_impulse, the frying pan):
## LMB a quick diagonal; RMB raises it overhead and holds the wind-up, releasing RMB brings it down, harder the
## longer it was held. At the clip's contact time whatever is in reach ahead takes the hit (ThrowImpactCapability,
## rigid bodies an impulse).

signal struck(impulse: float, hits: int)

const QUICK_ACTION: StringName = &"fire"
const HEAVY_ACTION: StringName = &"present_held"
const QUICK_CLIP: StringName = &"strike"
const HEAVY_CLIP: StringName = &"strike_heavy"
## Traced on Henry, upper body only (clip time): the quick diagonal swings the bowl out ahead at head height from
## 0.26 s (reach 0.6 m); Sword_Attack has it up and back overhead at 0.30 s (held while RMB is down) and the
## chop comes down to waist height 0.8 m ahead by 0.50 s.
const QUICK_FROM_S: float = 0.24
const QUICK_TO_S: float = 0.42  # the clip ends at 0.43 s
const HEAVY_WINDUP_S: float = 0.30
const HEAVY_TO_S: float = 0.68
## Paces of the clips (owner: not so fast): the quick swing, the rise to the wind-up, the chop once released.
const QUICK_PACE: float = 0.7
const HEAVY_WINDUP_PACE: float = 0.8
const HEAVY_RELEASE_PACE: float = 1.0
## A quick swing carries this share of the tool's full impulse; a held wind-up rises from HEAVY_MIN to 1 over CHARGE_S.
const QUICK_SHARE: float = 0.45
const HEAVY_MIN: float = 0.7
const CHARGE_S: float = 1.0
## The pan's own path is tested around the contact time: this long either side, and its striking radius (bowl).
const HIT_RADIUS_M: float = 0.16
## Only where the bowl is this far out ahead of Henry's centre does it strike (not his own side), metres.
const AHEAD_M: float = 0.25
## A quick strike clanks, a held one bongs (synthesised stand-ins, tools/audio/make_pan_hits.py).
const QUICK_HIT_EVENT: SoundEvent = preload("res://data/audio/items/pan_hit_quick.tres")
const HEAVY_HIT_EVENT: SoundEvent = preload("res://data/audio/items/pan_hit_heavy.tres")

enum State { IDLE, QUICK, WINDING, HELD, RELEASING }

@export var held: HeldItemComponent

var _state: State = State.IDLE
var _clip_s: float = 0.0
var _charge_s: float = 0.0
var _hit_done: bool = false
var _release_wanted: bool = false
var _share: float = 1.0
var _pace: float = 1.0
var _hits: int = 0
var _struck_ids: Dictionary = {}
var _last_bowl: Vector3 = Vector3.ZERO


func _ready() -> void:
	if held == null:
		held = get_parent().get_node_or_null(^"HeldItemComponent") as HeldItemComponent


## The full impulse of the tool now in hand, 0 when it is not one Henry swings.
func held_strike_impulse() -> float:
	if held == null or not held.is_holding():
		return 0.0
	var item: ItemResource = ItemCatalog.get_item(held.get_item_id())
	return item.strike_impulse if item != null else 0.0


func is_striking() -> bool:
	return _state != State.IDLE


## Before Quick Access and the held-item hint take LMB/RMB: with a swung tool in hand they are its strikes.
func _input(event: InputEvent) -> void:
	if event.is_echo() or held_strike_impulse() <= 0.0 or _hub_open():
		return
	if event.is_action_pressed(QUICK_ACTION) and _state == State.IDLE:
		_start(QUICK_CLIP, State.QUICK)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed(HEAVY_ACTION) and _state == State.IDLE:
		_start(HEAVY_CLIP, State.WINDING)
		get_viewport().set_input_as_handled()
	elif event.is_action_released(HEAVY_ACTION) and _state in [State.WINDING, State.HELD]:
		_release_wanted = true
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	match _state:
		State.QUICK:
			_clip_s += delta * _pace
			_sweep(QUICK_FROM_S, QUICK_TO_S, QUICK_SHARE)
			if _clip_s >= _visual_length(QUICK_CLIP):
				_state = State.IDLE
		State.WINDING:
			_clip_s += delta * _pace
			if _clip_s >= HEAVY_WINDUP_S:
				_visual().hold_upper_action_at(HEAVY_WINDUP_S)
				_clip_s = HEAVY_WINDUP_S
				_charge_s = 0.0
				_state = State.HELD
		State.HELD:
			_charge_s = minf(_charge_s + delta, CHARGE_S)
			if _release_wanted:
				_visual().set_upper_action_pace(HEAVY_RELEASE_PACE)
				_state = State.RELEASING
		State.RELEASING:
			_clip_s += delta * HEAVY_RELEASE_PACE
			_sweep(HEAVY_WINDUP_S, HEAVY_TO_S, lerpf(HEAVY_MIN, 1.0, _charge_s / CHARGE_S))
			if _clip_s >= _visual_length(HEAVY_CLIP):
				_state = State.IDLE
	if _state != State.IDLE and held_strike_impulse() <= 0.0:
		_state = State.IDLE


func _start(clip: StringName, state: State) -> void:
	var visual: HenryUALAnimation = _visual()
	var pace: float = QUICK_PACE if state == State.QUICK else HEAVY_WINDUP_PACE
	if visual == null or not visual.play_upper_action(clip, pace):
		return
	_pace = pace
	_state = state
	_clip_s = 0.0
	_hit_done = false
	_release_wanted = false
	_hits = 0
	_struck_ids.clear()
	_last_bowl = _bowl_centre()


## Through the swing's active part the bowl's whole path since the last frame is tested (spheres along the
## segment: a swept hit, as melee weapons are traced, so a fast swing cannot pass through something between
## frames); only while it is out ahead of Henry. Each thing is struck once; the window's end reports the swing.
func _sweep(from_s: float, to_s: float, share: float) -> void:
	if _hit_done:
		return
	var bowl: Vector3 = _bowl_centre()
	if _clip_s >= from_s:
		var body := get_parent() as Node3D
		var forward: Vector3 = -body.global_basis.z
		var steps: int = maxi(1, ceili(_last_bowl.distance_to(bowl) / (HIT_RADIUS_M * 0.75)))
		for k: int in range(1, steps + 1):
			var at: Vector3 = _last_bowl.lerp(bowl, float(k) / float(steps))
			if (at - body.global_position).dot(forward) > AHEAD_M:
				_hits += _strike_at(at, share)
	_last_bowl = bowl
	if _clip_s >= to_s:
		_hit_done = true
		var sound: Node = get_node_or_null(^"/root/SoundSystem")
		if sound != null and _hits > 0:
			sound.call(&"play", QUICK_HIT_EVENT if _state == State.QUICK else HEAVY_HIT_EVENT, bowl)
		struck.emit(held_strike_impulse() * share, _hits)


## The striking part of the tool now: the held prop's own origin (the pan's bowl centre).
func _bowl_centre() -> Vector3:
	var prop: Node3D = held.get_held_prop() if held != null else null
	return prop.global_position if prop != null else (get_parent() as Node3D).global_position


## Everything the bowl overlaps at `centre` not struck yet this swing: rigid bodies get the impulse along the
## swing's facing, ThrowImpactCapability targets the hit. Returns how many it struck now.
func _strike_at(centre: Vector3, share: float) -> int:
	var body := get_parent() as Node3D
	var impulse: float = held_strike_impulse() * share
	var forward: Vector3 = -body.global_basis.z
	forward.y = 0.0
	forward = forward.normalized()
	var query := PhysicsShapeQueryParameters3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = HIT_RADIUS_M
	query.shape = sphere
	query.transform = Transform3D(Basis.IDENTITY, centre)
	query.collide_with_areas = false
	if body is CollisionObject3D:
		query.exclude = [(body as CollisionObject3D).get_rid()]
	var hits: int = 0
	var found: Array[Dictionary] = body.get_world_3d().direct_space_state.intersect_shape(query, 16)
	for result: Dictionary in found:
		var collider: Object = result.get("collider")
		if collider == null or _struck_ids.has(collider) or (collider is Node and body.is_ancestor_of(collider as Node)):
			continue
		_struck_ids[collider] = true
		if collider is RigidBody3D:
			(collider as RigidBody3D).apply_central_impulse(forward * impulse)
			hits += 1
		elif ThrowImpactCapability.hit(_impact_target(collider), held.get_item_id(), centre, -forward, impulse, collider):
			hits += 1
	return hits


## The collider or the nearest ancestor that takes hits (as a thrown item finds a pane's window).
func _impact_target(collider: Object) -> Object:
	var node := collider as Node
	for _i: int in range(3):
		if node == null:
			break
		if CapabilityContract.has(node, ThrowImpactCapability.ID):
			return node
		node = node.get_parent()
	return collider


func _visual() -> HenryUALAnimation:
	return get_parent().get_node_or_null(^"HenryUALVisual") as HenryUALAnimation


func _visual_length(clip: StringName) -> float:
	var visual: HenryUALAnimation = _visual()
	return visual.get_action_length(clip) if visual != null else 0.5


func _hub_open() -> bool:
	var hub := get_parent().get_node_or_null(^"PlayerHubComponent") as PlayerHubComponent
	return hub != null and hub.is_open()
