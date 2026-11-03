extends CharacterBody3D

## A scripted INPUT driver for the demonstration. The actual wall-run lives in
## short_wall_run.gd, and movement is resolved with move_and_slide() each tick.

const WALL_RUN = preload("res://tests/demos/wallrun/short_wall_run.gd")

var wall_run: ShortWallRun
var section: int = 0
var segment_time: float = 0.0
var camera_roll: float = 0.0
var target_roll: float = 0.0
var remaining_ratio: float = 0.0
var phase_caption: String = "SPRINT"
var wall_side: int = -1
var _jumped: bool = false

const SEGMENT_DURATION: float = 3.85
const GRAVITY: float = 9.8


func _ready() -> void:
    collision_layer = 2
    collision_mask = 1
    var shape := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.34
    capsule.height = 1.85
    shape.shape = capsule
    add_child(shape)

    var mesh := MeshInstance3D.new()
    var skin := CapsuleMesh.new()
    skin.radius = 0.34
    skin.height = 1.85
    mesh.mesh = skin
    var mat := StandardMaterial3D.new()
    mat.albedo_color = Color(0.86, 0.57, 0.35)
    mat.roughness = 1.0
    mesh.material_override = mat
    add_child(mesh)

    var forward_mark := MeshInstance3D.new()
    var mark_mesh := BoxMesh.new()
    mark_mesh.size = Vector3(0.28, 0.54, 0.11)
    forward_mark.mesh = mark_mesh
    var mark_mat := StandardMaterial3D.new()
    mark_mat.albedo_color = Color(0.98, 0.93, 0.70)
    mark_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    forward_mark.material_override = mark_mat
    forward_mark.position = Vector3(0.0, 0.25, -0.3)
    add_child(forward_mark)

    var left := RayCast3D.new()
    left.name = "LeftWallRay"
    left.position = Vector3(0.0, 0.3, 0.0)
    left.target_position = Vector3(-1.25, 0.0, 0.0)
    left.collision_mask = 1
    left.exclude_parent = true
    left.enabled = true
    add_child(left)

    var right := RayCast3D.new()
    right.name = "RightWallRay"
    right.position = Vector3(0.0, 0.3, 0.0)
    right.target_position = Vector3(1.25, 0.0, 0.0)
    right.collision_mask = 1
    right.exclude_parent = true
    right.enabled = true
    add_child(right)

    wall_run = WALL_RUN.new()
    wall_run.name = "ShortWallRun"
    add_child(wall_run)
    wall_run.body = self
    wall_run.left_probe = left
    wall_run.right_probe = right
    wall_run.wall_run_started.connect(_on_wall_run_started)
    wall_run.wall_run_progress.connect(_on_wall_run_progress)
    wall_run.wall_run_finished.connect(_on_wall_run_finished)
    _reset_section(0)


func _physics_process(delta: float) -> void:
    segment_time += delta
    if segment_time >= SEGMENT_DURATION and section == 0:
        _reset_section(1)

    var forward := Vector3(0.0, 0.0, -1.0)
    if is_on_floor() and not _jumped and segment_time >= 0.92:
        velocity.y = 6.0
        _jumped = true

    # Only the component handles horizontal speed + gravity while wall-running.
    var active := wall_run.physics_step(delta, forward, true)
    if not active:
        velocity.x = move_toward(velocity.x, 0.0, 12.0 * delta)
        velocity.z = move_toward(velocity.z, -10.0, 30.0 * delta)
        if not is_on_floor():
            velocity.y -= GRAVITY * delta
        elif not _jumped:
            velocity.y = -0.1

    move_and_slide()
    if not active:
        if segment_time < 0.92:
            phase_caption = "GROUND SPRINT"
        elif segment_time < 1.6:
            phase_caption = "TAKEOFF"
        else:
            phase_caption = "RELEASE / FALL"

    camera_roll = lerpf(camera_roll, target_roll, 1.0 - exp(-9.0 * delta))


func _reset_section(new_section: int) -> void:
    section = new_section
    wall_side = -1 if section == 0 else 1
    segment_time = 0.0
    _jumped = false
    position = Vector3(0.63 * float(wall_side), 1.1, 5.0)
    velocity = Vector3.ZERO
    camera_roll = 0.0
    target_roll = 0.0
    remaining_ratio = 0.0
    phase_caption = "GROUND SPRINT"
    if wall_run != null:
        wall_run.reset_after_teleport()


func _on_wall_run_started(side: int) -> void:
    target_roll = -13.0 * float(side)
    phase_caption = "WALL RUN"


func _on_wall_run_progress(value: float) -> void:
    remaining_ratio = value


func _on_wall_run_finished() -> void:
    target_roll = 0.0
    remaining_ratio = 0.0
    phase_caption = "RELEASE / FALL"


func horizontal_speed() -> float:
    return Vector2(velocity.x, velocity.z).length()
