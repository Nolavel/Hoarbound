extends CharacterBody3D

## First-person gap-crossing demo driver. No teleports after start and no
## position animation: all movement uses velocity + CharacterBody3D.move_and_slide().
## The physics component is res://tests/demos/wallrun/short_wall_run.gd.

const WALL_RUN = preload("res://tests/demos/wallrun/short_wall_run.gd")
const GAP_NEAR: float = 1.5
const GAP_FAR: float = -9.5
const GRAVITY: float = 9.8

var wall_run: ShortWallRun
var elapsed: float = 0.0
var camera_roll: float = 0.0
var target_roll: float = 0.0
var remaining_ratio: float = 0.0
var phase_caption: String = "APPROACH"
var wall_side: int = -1
var jumped: bool = false
var entered_gap: bool = false
var crossed_gap: bool = false
var landed_far: bool = false
var crossed_at: float = -1.0
var landed_at: float = -1.0
var min_height_over_gap: float = INF
var last_wall_run_side: int = 0


func _ready() -> void:
    collision_layer = 2
    collision_mask = 1

    var capsule_node := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.34
    capsule.height = 1.85
    capsule_node.shape = capsule
    add_child(capsule_node)

    var left := RayCast3D.new()
    left.name = "LeftWallRay"
    left.position = Vector3(0.0, 0.18, 0.0)
    left.target_position = Vector3(-1.3, 0.0, 0.0)
    left.collision_mask = 1
    left.exclude_parent = true
    left.enabled = true
    add_child(left)

    var right := RayCast3D.new()
    right.name = "RightWallRay"
    right.position = Vector3(0.0, 0.18, 0.0)
    right.target_position = Vector3(1.3, 0.0, 0.0)
    right.collision_mask = 1
    right.exclude_parent = true
    right.enabled = true
    add_child(right)

    wall_run = WALL_RUN.new()
    wall_run.name = "ShortWallRun"
    wall_run.body = self
    wall_run.left_probe = left
    wall_run.right_probe = right
    wall_run.max_duration = 0.85
    wall_run.target_speed = 17.0
    wall_run.entry_lift = 0.55
    add_child(wall_run)
    wall_run.wall_run_started.connect(_on_wall_run_started)
    wall_run.wall_run_progress.connect(_on_wall_run_progress)
    wall_run.wall_run_finished.connect(_on_wall_run_finished)

    global_position = Vector3(-0.67, 0.93, 12.0)


func _physics_process(delta: float) -> void:
    elapsed += delta
    var on_floor_before := is_on_floor()

    # The single timed jump is only the INPUT trigger. The crossing happens
    # with actual wall contact, acceleration and scaled gravity.
    if on_floor_before and not jumped and elapsed >= 0.91:
        velocity.y = 3.0
        jumped = true

    var active: bool = wall_run.physics_step(delta, Vector3.FORWARD, jumped)
    if not active:
        velocity.x = move_toward(velocity.x, 0.0, 16.0 * delta)
        velocity.z = move_toward(velocity.z, -10.0, 30.0 * delta)
        if not on_floor_before:
            velocity.y -= GRAVITY * delta
        elif not jumped:
            velocity.y = -0.1

    move_and_slide()

    if jumped and global_position.z <= GAP_NEAR:
        entered_gap = true
    if entered_gap and global_position.z <= GAP_FAR:
        crossed_gap = true
        if crossed_at < 0.0:
            crossed_at = elapsed
    if global_position.z <= GAP_NEAR and global_position.z > GAP_FAR:
        min_height_over_gap = minf(min_height_over_gap, global_position.y)

    if crossed_gap and is_on_floor() and not landed_far:
        landed_far = true
        landed_at = elapsed

    if landed_far:
        phase_caption = "LANDED / GAP CLEARED"
    elif active and entered_gap:
        phase_caption = "WALL RUN / ABOVE THE DROP"
    elif active:
        phase_caption = "WALL RUN / ACCELERATING"
    elif crossed_gap:
        phase_caption = "FAR SIDE / DESCENDING"
    elif jumped:
        phase_caption = "JUMP / GRAB WALL"
    else:
        phase_caption = "APPROACH / SPRINT"

    camera_roll = lerpf(camera_roll, target_roll, 1.0 - exp(-10.0 * delta))


func _on_wall_run_started(side: int) -> void:
    last_wall_run_side = side
    # Exactly as in Arena_Stacktrace/player.gd: the camera roll is
    # -angle * sign(player_right.dot(wall_normal)).
    # Here a LEFT wall has inward normal +X -> negative camera roll.
    target_roll = 13.0 * float(side)
    phase_caption = "WALL RUN / ACCELERATING"


func _on_wall_run_progress(ratio: float) -> void:
    remaining_ratio = ratio


func _on_wall_run_finished() -> void:
    target_roll = 0.0
    remaining_ratio = 0.0


func horizontal_speed() -> float:
    return Vector2(velocity.x, velocity.z).length()
