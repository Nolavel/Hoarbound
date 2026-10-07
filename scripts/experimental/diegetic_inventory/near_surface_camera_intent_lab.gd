class_name NearSurfaceCameraIntentLab
extends Node

## Issue #203 lab-only pre-focus camera intent.
##
## Exact small-item focus can become geometrically impossible when Henry is flush
## to a low table: the normal long TPS orbit needs more than the production -70°
## pitch before the centre ray can reach the tabletop. This intent changes only
## boom distance when Henry is already at a nearby authored surface and the player
## is looking down. It never changes yaw/pitch, shoulder side or Henry's body.

const TABLE_FRONT_Z_M: float = 0.20
const MAX_FRONT_GAP_M: float = 0.72
const LOOK_DOWN_THRESHOLD_DEG: float = -12.0
const INTENT_NEAR_DISTANCE_M: float = 0.88
const INTENT_FAR_DISTANCE_M: float = 1.45

var stage: DiegeticInventoryStage
var active: bool = true
var engaged: bool = false


func setup(stage_node: DiegeticInventoryStage) -> void:
	stage = stage_node
	## Stage focus framing writes its scene-only distances at -20. Override only the
	## eligible pre-focus boom after that, before production TpsCamera processes.
	process_priority = -15
	set_process(true)


func _process(_delta: float) -> void:
	engaged = false
	if not active or not is_instance_valid(stage) or not is_instance_valid(stage.table):
		return
	var local_root: Vector3 = stage.table.to_local(stage.player.global_position)
	var front_gap: float = local_root.z - TABLE_FRONT_Z_M
	if front_gap < 0.0 or front_gap > MAX_FRONT_GAP_M:
		return
	if stage.camera.get_view_pitch_deg() > LOOK_DOWN_THRESHOLD_DEG:
		return
	engaged = true
	stage.camera.near_distance = minf(stage.camera.near_distance, INTENT_NEAR_DISTANCE_M)
	stage.camera.far_distance = minf(stage.camera.far_distance, INTENT_FAR_DISTANCE_M)


func get_report() -> Dictionary:
	return {
		"engaged": engaged,
		"max_front_gap_m": MAX_FRONT_GAP_M,
		"look_down_threshold_deg": LOOK_DOWN_THRESHOLD_DEG,
		"intent_near_distance_m": INTENT_NEAR_DISTANCE_M,
		"intent_far_distance_m": INTENT_FAR_DISTANCE_M,
		"changes_yaw_or_pitch": false,
		"changes_shoulder": false,
		"moves_henry": false,
	}
