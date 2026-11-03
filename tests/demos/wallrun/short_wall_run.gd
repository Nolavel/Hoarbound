extends Node
class_name ShortWallRun

## Self-contained short wall-run. Caller owns move_and_slide().
## The actor's normal movement/gravity must not overwrite velocity while active.

signal wall_run_started(side: int)
signal wall_run_progress(remaining_ratio: float)
signal wall_run_finished()

@export var body: CharacterBody3D
@export var left_probe: RayCast3D
@export var right_probe: RayCast3D
@export var min_entry_speed: float = 7.0
@export var target_speed: float = 17.0
@export var acceleration: float = 20.0
@export var max_duration: float = 0.8
@export var gravity_scale: float = 0.38
@export var entry_lift: float = 0.8
@export var wall_push: float = 0.7
@export var contact_grace_time: float = 0.07
@export_range(0.0, 1.0) var min_parallel_input: float = 0.55
@export_range(0.0, 1.0) var min_entry_alignment: float = 0.35
@export_range(0.0, 1.0) var max_wall_up_dot: float = 0.2

var is_running: bool = false
var _used_in_air: bool = false
var _elapsed: float = 0.0
var _speed: float = 0.0
var _side: int = 0
var _last_wall_normal: Vector3 = Vector3.ZERO
var _contact_grace_left: float = 0.0


func physics_step(delta: float, wish_direction: Vector3, wants_to_run: bool) -> bool:
    if body == null or left_probe == null or right_probe == null:
        return false
    if body.is_on_floor():
        _finish()
        _used_in_air = false
        return false
    if not wants_to_run or wish_direction.length_squared() < 0.01:
        _finish()
        return false
    if is_running and _elapsed >= max_duration:
        _finish()
        return false

    var flat_wish := Vector3(wish_direction.x, 0.0, wish_direction.z)
    if flat_wish.length_squared() < 0.01:
        _finish()
        return false
    flat_wish = flat_wish.normalized()

    var normal: Vector3 = Vector3.ZERO
    if is_running:
        var active_probe: RayCast3D = left_probe if _side == -1 else right_probe
        normal = _wall_normal(active_probe)
        if normal == Vector3.ZERO:
            _contact_grace_left -= delta
            if _contact_grace_left <= 0.0:
                _finish()
                return false
            normal = _last_wall_normal
        else:
            _contact_grace_left = contact_grace_time
            _last_wall_normal = normal
    else:
        if _used_in_air:
            return false
        var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
        if horizontal.length() < min_entry_speed:
            return false
        for candidate_side: int in [-1, 1]:
            var probe: RayCast3D = left_probe if candidate_side == -1 else right_probe
            var candidate_normal := _wall_normal(probe)
            if candidate_normal == Vector3.ZERO:
                continue
            var candidate_along := _along_wall(flat_wish, candidate_normal)
            if candidate_along == Vector3.ZERO:
                continue
            if flat_wish.dot(candidate_along) < min_parallel_input:
                continue
            if horizontal.normalized().dot(candidate_along) < min_entry_alignment:
                continue
            normal = candidate_normal
            _side = candidate_side
            break
        if normal == Vector3.ZERO:
            return false

    var along := _along_wall(flat_wish, normal)
    if along == Vector3.ZERO or flat_wish.dot(along) < min_parallel_input:
        _finish()
        return false

    if not is_running:
        is_running = true
        _used_in_air = true
        _elapsed = 0.0
        _last_wall_normal = normal
        _contact_grace_left = contact_grace_time
        var horizontal := Vector3(body.velocity.x, 0.0, body.velocity.z)
        _speed = maxf(horizontal.dot(along), 0.0)
        body.velocity.y = maxf(body.velocity.y, entry_lift)
        wall_run_started.emit(_side)
        wall_run_progress.emit(1.0)

    _speed = minf(_speed + acceleration * delta, maxf(_speed, target_speed))
    var horizontal_result := along * _speed - normal * wall_push
    body.velocity.x = horizontal_result.x
    body.velocity.z = horizontal_result.z

    var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
    body.velocity.y -= gravity * gravity_scale * delta
    _elapsed = minf(_elapsed + delta, max_duration)
    wall_run_progress.emit(1.0 - _elapsed / maxf(max_duration, 0.001))
    return true


func reset_after_teleport() -> void:
    _finish()
    _used_in_air = false


func _wall_normal(probe: RayCast3D) -> Vector3:
    probe.force_raycast_update()
    if not probe.is_colliding():
        return Vector3.ZERO
    var normal := probe.get_collision_normal().normalized()
    if absf(normal.dot(Vector3.UP)) > max_wall_up_dot:
        return Vector3.ZERO
    return normal


func _along_wall(wish: Vector3, normal: Vector3) -> Vector3:
    var projected := wish.slide(normal)
    projected.y = 0.0
    if projected.length_squared() < 0.0001:
        return Vector3.ZERO
    return projected.normalized()


func _finish() -> void:
    if not is_running:
        return
    is_running = false
    _elapsed = 0.0
    _side = 0
    _speed = 0.0
    wall_run_finished.emit()
